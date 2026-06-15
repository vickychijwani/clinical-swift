import SQLiteData
import SwiftUI

struct PatientsView: View {
    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientListRow]
    @State private var searchText = ""
    @State private var isAddingPatient = false
    @State private var viewingPatient: PatientListItem? = nil

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patientListItems,
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
                    .background(Color("AppBackground"))
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $viewingPatient) { item in
            let patientDetails = PatientDetails(
                patient: item.patient,
                nextAppointmentDate: item.nextAppointmentDate
            )
            NavigationStack {
                ViewPatientView(details: patientDetails)
                    .background(Color("AppBackground"))
            }
            .presentationDetents([.medium])
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
        PatientsView()
    }
}
