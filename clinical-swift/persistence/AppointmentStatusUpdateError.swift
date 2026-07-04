nonisolated enum AppointmentStatusUpdateError: Error, Equatable, Sendable {
    case unavailable
    case invalidStoredStatus(String)
    case transition(AppointmentStatusTransitionError)
}
