import SwiftUI

struct PatientsView: View {
    let patients: [Patient]
    var referenceDate: Date = .now
    var calendar: Calendar = .autoupdatingCurrent
    var locale: Locale = .autoupdatingCurrent

    @State private var searchText = ""

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patients,
                searchText: searchText,
                locale: locale
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            searchText: $searchText
        )
        .background(Color("AppBackground"))
        .navigationTitle("Patients")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {}
            }
        }
    }
}

#Preview {
    PatientsView(
        patients: samplePatients,
        referenceDate: Date.now
    )
}
