import SwiftUI

struct PatientList: View {
    let sections: [PatientSection]
    let referenceDate: Date
    let calendar: Calendar
    let locale: Locale

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.patients) { patient in
                        PatientRow(
                            patient: patient,
                            referenceDate: referenceDate,
                            calendar: calendar,
                            locale: locale
                        )
                    }
                } header: {
                    Text(section.id)
                        .font(.title3.bold())
                }
                .sectionIndexLabel(section.id)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    PatientList(
        sections: PatientSection.sections(from: samplePatients),
        referenceDate: .now,
        calendar: .autoupdatingCurrent,
        locale: .autoupdatingCurrent
    )
    .background(Color("AppBackground"))
}
