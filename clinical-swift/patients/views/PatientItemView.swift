import SwiftUI

struct PatientItemView: View {
    let item: PatientDetails

    private var patient: Patient {
        item.patient
    }

    var body: some View {
        HStack(spacing: 12) {
            PatientAvatar(patient: patient)

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.displayName)
                    .styleBodyBold()
                    .lineLimit(1)

                if let subtitle = PatientItemViewMetadata.metadata(for: item)
                    .subtitle
                {
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
