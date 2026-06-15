import Dependencies
import SwiftUI

struct PatientRow: View {
    let item: PatientListItem
    @ObservationIgnored @Dependency(\.date.now) var referenceDate: Date
    @ObservationIgnored @Dependency(\.calendar) var calendar: Calendar
    @ObservationIgnored @Dependency(\.locale) var locale: Locale

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

                if let subtitle = PatientMetadata.metadata(for: item)
                    .subtitle {
                        Text(subtitle)
                            .styleCaption()
                            .lineLimit(2)
                    }
            }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    PatientRow(item: samplePatientListItems[0])
    .padding(8)
}
