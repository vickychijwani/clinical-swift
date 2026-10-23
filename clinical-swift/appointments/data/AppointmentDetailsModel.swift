import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

@MainActor @Observable
final class AppointmentDetailsModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @FetchOne private var row: AppointmentPatientSelection?

    let appointmentID: Appointment.ID
    private let statusUpdater: StatusUpdater?

    private(set) var errorMessage: String?
    private(set) var isUpdatingStatus = false

    init(
        appointmentID: Appointment.ID,
        statusUpdater: StatusUpdater? = nil
    ) {
        self.appointmentID = appointmentID
        self.statusUpdater = statusUpdater
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

    func dismissError() {
        errorMessage = nil
    }

    func load() async throws {
        try await $row.load(appointmentDetailsQuery(id: appointmentID))
    }

    func updateStatus(to requestedStatus: Appointment.Status) async -> Bool {
        guard !isUpdatingStatus else { return false }

        errorMessage = nil
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            if let statusUpdater {
                _ = try await statusUpdater(appointmentID, requestedStatus, now)
            } else {
                _ = try await database.updateAppointmentStatus(
                    id: appointmentID,
                    to: requestedStatus,
                    at: now
                )
            }
            return true
        } catch let error as AppointmentStatusUpdateError {
            await handleStatusUpdateError(error)
            return false
        } catch {
            errorMessage = "The appointment could not be updated."
            return false
        }
    }

    private func handleStatusUpdateError(_ error: AppointmentStatusUpdateError) async {
        switch error {
        case .transition(.invalidTransition(let currentStatus, _)):
            _ = try? await $row.load(appointmentDetailsQuery(id: appointmentID))
            switch currentStatus {
            case .completed:
                errorMessage = "This appointment was already completed."
            case .cancelled:
                errorMessage = "This appointment was already cancelled."
            case .draft, .scheduled:
                errorMessage = "This appointment was already updated."
            }

        case .unavailable:
            _ = try? await $row.load(appointmentDetailsQuery(id: appointmentID))
            errorMessage = "This appointment is no longer available."

        case .invalidStoredStatus, .transition(.transientStatus):
            errorMessage = "The appointment could not be updated."
        }
    }

    typealias StatusUpdater =
        @MainActor @Sendable (
            Appointment.ID,
            Appointment.Status,
            Date
        ) async throws -> AppointmentStatusUpdateResult
}
