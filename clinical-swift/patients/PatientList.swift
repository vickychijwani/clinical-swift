import SwiftUI

struct PatientList: View {
    let sections: [PatientSection]
    let referenceDate: Date
    let calendar: Calendar
    let locale: Locale

    @Binding var searchText: String

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        PatientRow(
                            item: item,
                            referenceDate: referenceDate,
                            calendar: calendar,
                            locale: locale
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                    }
                } header: {
                    Text(section.id)
                }
                .sectionIndexLabel(section.id)
            }
        }
        .searchable(text: $searchText)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    PatientList(
        sections: PatientSection.sections(from: samplePatientListItems),
        referenceDate: .now,
        calendar: .autoupdatingCurrent,
        locale: .autoupdatingCurrent,
        searchText: .constant("")
    )
    .background(Color("AppBackground"))
}
