import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable
final class AppointmentDetailsModel {
    @ObservationIgnored @FetchOne private var row: AppointmentPatientSelection?
    @ObservationIgnored private let statusUpdater = AppointmentStatusUpdateModel()

    let appointmentID: Appointment.ID

    init(appointmentID: Appointment.ID) {
        self.appointmentID = appointmentID
        _row = FetchOne(appointmentDetailsQuery(id: appointmentID))
    }

    var details: AppointmentDetails? {
        row?.details
    }

    var showsStatusActions: Bool {
        details?.appointment.status == .scheduled
    }

    var showsMessagingAction: Bool {
        details?.appointment.status == .scheduled
    }

    var errorMessage: String? {
        statusUpdater.errorMessage
    }

    var isUpdatingStatus: Bool {
        statusUpdater.isUpdating
    }

    func dismissError() {
        statusUpdater.dismissError()
    }

    func load() async throws {
        try await $row.load(appointmentDetailsQuery(id: appointmentID))
    }

    func updateStatus(to requestedStatus: Appointment.Status) async -> Bool {
        await statusUpdater.updateStatus(
            for: appointmentID,
            to: requestedStatus
        ) {
            _ = try? await $row.load(appointmentDetailsQuery(id: appointmentID))
        }
    }
}

/// Shared status-update workflow so both appointment details surfaces enforce the same
/// submission guard, telemetry, and conflict messages.
@MainActor @Observable
final class AppointmentStatusUpdateModel {
    @ObservationIgnored @Dependency(\.appointmentStatusClient) private var statusClient
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    func dismissError() {
        errorMessage = nil
    }

    func updateStatus(
        for appointmentID: Appointment.ID,
        to requestedStatus: Appointment.Status,
        onStaleRecord: @MainActor () async -> Void = {}
    ) async -> Bool {
        guard !isUpdating else { return false }

        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false }

        do {
            _ = try await statusClient.updateStatus(appointmentID, requestedStatus, now)
            telemetry.event(
                category: .appointment,
                name: "appointment_status_updated",
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            return true
        } catch let error as AppointmentStatusUpdateError {
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_status_update_failed",
                message: "Appointment status update rejected",
                error: error,
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            await handleError(error, onStaleRecord: onStaleRecord)
            return false
        } catch {
            telemetry.log(
                .error,
                category: .appointment,
                name: "appointment_status_update_failed",
                message: "Appointment status update failed",
                error: error,
                recordID: appointmentID.uuidString.lowercased(),
                status: requestedStatus.rawValue
            )
            errorMessage = "The appointment could not be updated."
            return false
        }
    }

    private func handleError(
        _ error: AppointmentStatusUpdateError,
        onStaleRecord: @MainActor () async -> Void
    ) async {
        switch error {
        case .transition(.invalidTransition(let currentStatus, _)):
            await onStaleRecord()
            switch currentStatus {
            case .completed:
                errorMessage = "This appointment was already completed."
            case .cancelled:
                errorMessage = "This appointment was already cancelled."
            case .draft, .scheduled:
                errorMessage = "This appointment was already updated."
            }

        case .unavailable:
            await onStaleRecord()
            errorMessage = "This appointment is no longer available."

        case .invalidStoredStatus, .transition(.transientStatus):
            errorMessage = "The appointment could not be updated."
        }
    }
}

nonisolated struct AppointmentStatusClient: DependencyKey, Sendable {
    var updateStatus:
        @Sendable (
            _ id: Appointment.ID,
            _ requestedStatus: Appointment.Status,
            _ updatedAt: Date
        ) async throws -> AppointmentStatusUpdateResult

    static let liveValue = Self { id, requestedStatus, updatedAt in
        @Dependency(\.defaultDatabase) var database
        return try await database.updateAppointmentStatus(
            id: id,
            to: requestedStatus,
            at: updatedAt
        )
    }

    static let testValue = liveValue
}

extension DependencyValues {
    nonisolated var appointmentStatusClient: AppointmentStatusClient {
        get { self[AppointmentStatusClient.self] }
        set { self[AppointmentStatusClient.self] = newValue }
    }
}
