import SwiftUI

struct PatientsView: View {
    let patients: [Patient]
    var referenceDate: Date = .now
    var calendar: Calendar = .autoupdatingCurrent
    var locale: Locale = .autoupdatingCurrent

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            PatientSearchField(text: $searchText)
                .padding()

            PatientList(
                sections: PatientSection.sections(
                    from: patients,
                    searchText: searchText,
                    locale: locale
                ),
                referenceDate: referenceDate,
                calendar: calendar,
                locale: locale
            )
        }
        .background(Color("AppBackground"))
    }
}

#Preview {
    PatientsView(
        patients: samplePatients,
        referenceDate: Date.now
    )
}
