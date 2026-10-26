import ClinicalModels
import SwiftUI

struct PatientSummaryView: View {
    private let patientItemView: PatientItemView
    private let patient: Patient
    private let onSelect: (@MainActor @Sendable () -> Void)?

    init(
        item: PatientDetails,
        onNameVisibilityChange: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        patientItemView = PatientItemView(
            item: item,
            onNameVisibilityChange: onNameVisibilityChange
        )
        patient = item.patient
        onSelect = nil
    }

    init(
        patient: Patient,
        onSelect: @escaping @MainActor @Sendable () -> Void
    ) {
        patientItemView = PatientItemView(patient: patient)
        self.patient = patient
        self.onSelect = onSelect
    }

    var body: some View {
        HStack {
            if let onSelect {
                Button(action: onSelect) {
                    patientItemView
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                patientItemView
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PatientContactActionsView(patient: patient)

            if let onSelect {
                Button(
                    "View Patient",
                    systemImage: "chevron.forward",
                    action: onSelect
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
            }
        }
    }
}
