nonisolated struct AppointmentStatusPresentation: Equatable, Sendable {
    let label: String
    let treatment: Treatment

    init(status: Appointment.Status) {
        switch status {
        case .scheduled:
            label = "Scheduled"
            treatment = .active
        case .completed:
            label = "Completed"
            treatment = .muted
        case .draft:
            label = "Draft"
            treatment = .accent
        case .cancelled:
            label = "Cancelled"
            treatment = .muted
        }
    }

    enum Treatment: Equatable, Sendable {
        case active
        case accent
        case muted
    }
}
