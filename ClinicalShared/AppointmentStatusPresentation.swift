import ClinicalModels
nonisolated struct AppointmentStatusPresentation: Equatable, Sendable {
    let label: String
    let systemImage: String
    let treatment: Treatment

    init(status: Appointment.Status) {
        switch status {
        case .scheduled:
            label = "Scheduled"
            systemImage = "clock"
            treatment = .active
        case .completed:
            label = "Completed"
            systemImage = "checkmark.circle"
            treatment = .muted
        case .draft:
            label = "Draft"
            systemImage = "clock"
            treatment = .accent
        case .cancelled:
            label = "Cancelled"
            systemImage = "xmark.circle"
            treatment = .muted
        }
    }

    enum Treatment: Equatable, Sendable {
        case active
        case accent
        case muted
    }
}
