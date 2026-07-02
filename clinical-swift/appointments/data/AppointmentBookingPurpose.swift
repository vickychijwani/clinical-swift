import Foundation

nonisolated enum AppointmentBookingPurpose: Equatable, Sendable {
    case create
    case edit(Appointment.ID)

    var title: String {
        switch self {
        case .create:
            "New Appointment"
        case .edit:
            "Edit Appointment"
        }
    }

    var editedAppointmentID: Appointment.ID? {
        guard case .edit(let id) = self else { return nil }
        return id
    }
}
