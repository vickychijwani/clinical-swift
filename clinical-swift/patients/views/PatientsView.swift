import SQLiteData
import SwiftUI

struct PatientsView: View {
    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientListRow]
    @State private var searchText = ""
    @State private var isAddingPatient = false
    @State private var viewingPatient: PatientDetails? = nil

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patientDetailsList,
                searchText: searchText
            ),
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
            }
        }
        .sheet(item: $viewingPatient) { item in
            NavigationStack {
                ViewPatientView(details: item)
            }
            .presentationDetents([.medium])
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
