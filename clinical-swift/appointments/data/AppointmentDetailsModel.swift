import Foundation
import SQLiteData

@MainActor @Observable
final class AppointmentDetailsModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @FetchOne private var row: ScheduleAppointmentRow?

    let appointmentID: Appointment.ID
    private let statusUpdater: StatusUpdater?

    private(set) var prompt: Prompt?
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

    func requestStatus(_ status: Appointment.Status) {
        guard showsStatusActions else { return }

        switch status {
        case .completed:
            prompt = .completeConfirmation
        case .cancelled:
            prompt = .cancelConfirmation
        case .draft, .scheduled:
            break
        }
    }

    func dismissPrompt() {
        prompt = nil
    }

    func load() async throws {
        try await $row.load(appointmentDetailsQuery(id: appointmentID))
    }

    func updateStatus(to requestedStatus: Appointment.Status) async -> Bool {
        guard !isUpdatingStatus else { return false }

        prompt = nil
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
            prompt = .error("The appointment could not be updated.")
            return false
        }
    }

    private func handleStatusUpdateError(_ error: AppointmentStatusUpdateError) async {
        switch error {
        case .transition(.invalidTransition(_, _)):
            _ = try? await $row.load(appointmentDetailsQuery(id: appointmentID))
            prompt = .error("This appointment was already updated.")

        case .unavailable:
            _ = try? await $row.load(appointmentDetailsQuery(id: appointmentID))
            prompt = .error("This appointment is no longer available.")

        case .invalidStoredStatus, .transition(.transientStatus):
            prompt = .error("The appointment could not be updated.")
        }
    }

    enum Prompt: Equatable {
        case completeConfirmation
        case cancelConfirmation
        case error(String)

        var title: String {
            switch self {
            case .completeConfirmation:
                "Complete appointment?"
            case .cancelConfirmation:
                "Cancel appointment?"
            case .error:
                "Unable to update appointment"
            }
        }

        var message: String {
            switch self {
            case .completeConfirmation:
                "Mark this appointment as completed?"
            case .cancelConfirmation:
                "This appointment will be hidden from the schedule and appointment history."
            case .error(let message):
                message
            }
        }
    }

    typealias StatusUpdater =
        @MainActor @Sendable (
            Appointment.ID,
            Appointment.Status,
            Date
        ) async throws -> AppointmentStatusUpdateResult
}
