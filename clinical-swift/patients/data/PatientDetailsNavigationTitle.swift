nonisolated enum PatientDetailsNavigationTitle {
    static let nameVisibilityThreshold = 0.01

    static func text(patientDisplayName: String, isNameVisible: Bool) -> String {
        isNameVisible ? "Patient Details" : patientDisplayName
    }
}
