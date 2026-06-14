import SQLiteData
import SwiftUI

struct PatientsView: View {
    var referenceDate: Date = .now
    var calendar: Calendar = .autoupdatingCurrent
    var locale: Locale = .autoupdatingCurrent

    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientListRow]
    @State private var searchText = ""
    @State private var isAddingPatient = false
    @State private var viewingPatient: PatientListItem? = nil

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patientListItems,
                searchText: searchText,
                locale: locale
            ),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale,
            searchText: $searchText,
            viewingPatient: $viewingPatient
        )
        .background(Color("AppBackground"))
        .navigationTitle("Patients")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {
                    isAddingPatient = true
                }
            }
        }
        .sheet(isPresented: $isAddingPatient) {
            NavigationStack {
                EditPatientView()
                    .background(Color("AppBackground"))
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $viewingPatient) { item in
            NavigationStack {
                Text("Patient \(item.patient.name)")
            }.presentationDetents([.medium])
        }
    }

    private var patientListItems: [PatientListItem] {
        patientRows.map(\.item)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        PatientsView(
            referenceDate: Date.now
        )
    }
}
