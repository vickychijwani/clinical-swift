nonisolated enum AppointmentStatusTransitionError: Error, Equatable, Sendable {
    case transientStatus
    case invalidTransition(
        current: Appointment.Status,
        requested: Appointment.Status
    )
}
