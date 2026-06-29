import SQLiteData
import SwiftUI

struct PatientsView: View {
    @Environment(Router.self) private var router

    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientListRow]
    @State private var searchText = ""
    @State private var isAddingPatient = false

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patientDetailsList,
                searchText: searchText
            ),
            onSelectPatient: { patientID in
                router.presentDetails(.patient(patientID))
            },
            searchText: $searchText
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
            }
        }
    }

    private var patientDetailsList: [PatientDetails] {
        patientRows.map(\.item)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        PatientsView()
    }
}
