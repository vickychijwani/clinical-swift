import ClinicalModels

nonisolated struct AppointmentStatusPresentation: Equatable, Sendable {
    let label: String
    let systemImage: String
    let statusColor: AppColor
    let timeColor: AppColor

    init(status: Appointment.Status) {
        switch status {
        case .draft:
            label = "Draft"
            systemImage = "clock"
            statusColor = .accent
            timeColor = .text
        case .scheduled:
            label = "Scheduled"
            systemImage = "clock"
            statusColor = .accent
            timeColor = .text
        case .completed:
            label = "Completed"
            systemImage = "checkmark.circle"
            statusColor = .success
            timeColor = .secondaryText
        // Cancelled appointments aren't displayed anywhere; configured just for completeness
        case .cancelled:
            label = "Cancelled"
            systemImage = "xmark.circle"
            statusColor = .secondaryText
            timeColor = .secondaryText
        }
    }
}
