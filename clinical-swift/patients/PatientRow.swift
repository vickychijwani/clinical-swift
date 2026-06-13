import SwiftUI

struct PatientRow: View {
    let item: PatientListItem
    let referenceDate: Date
    let calendar: Calendar
    let locale: Locale

    private var patient: Patient {
        item.patient
    }

    var body: some View {
        HStack(spacing: 12) {
            PatientAvatar(patient: patient)

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.displayName)
                    .font(.headline)
                    .lineLimit(1)

                if let subtitle = metadata.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var metadata: PatientMetadata {
        PatientMetadata.metadata(
            for: item,
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    PatientRow(
        item: samplePatientListItems[0],
        referenceDate: .now,
        calendar: .autoupdatingCurrent,
        locale: .autoupdatingCurrent
    )
    .padding(8)
}
