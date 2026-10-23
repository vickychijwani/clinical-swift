import ClinicalModels
import SwiftUI

struct PatientItemView: View {
    let patient: Patient
    let subtitle: String?
    let onNameVisibilityChange: (@MainActor @Sendable (Bool) -> Void)?

    init(
        item: PatientDetails,
        onNameVisibilityChange: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        patient = item.patient
        subtitle = PatientItemViewMetadata.metadata(for: item).subtitle
        self.onNameVisibilityChange = onNameVisibilityChange
    }

    init(patient: Patient) {
        self.patient = patient
        subtitle = PatientItemViewMetadata.demographics(for: patient)
        onNameVisibilityChange = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            PatientAvatar(patient: patient)

            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let onNameVisibilityChange {
                        Text(patient.displayName)
                            .onScrollVisibilityChange(
                                threshold: PatientDetailsNavigationTitle
                                    .nameVisibilityThreshold,
                                onNameVisibilityChange
                            )
                    } else {
                        Text(patient.displayName)
                    }
                }
                .styleBodyBold()
                .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .styleCaption()
                        .lineLimit(2)
                }
            }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    PatientItemView(item: samplePatientDetails[0])
        .padding(8)
}
