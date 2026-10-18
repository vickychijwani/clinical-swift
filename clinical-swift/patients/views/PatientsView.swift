import SQLiteData
import SwiftUI

struct PatientsView: View {
    @Environment(Router.self) private var router

    @FetchAll(patientListRowsQuery(), animation: .default)
    private var patientRows: [PatientDetailsSelection]
    @State private var searchText = ""
    @State private var externalPhoneNumbers: Set<String>?
    @State private var externalSearchText: String?

    var body: some View {
        PatientList(
            sections: PatientSection.sections(
                from: patientDetailsList,
                searchText: searchText,
                matchingPhoneNumbers: externalPhoneNumbers
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
                BackupSettingsButton()
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {
                    router.requestPatientCreation()
                }
            }
        }
        .task(id: router.patientSearchRequest?.id) {
            guard let request = router.patientSearchRequest else { return }
            externalPhoneNumbers = request.phoneNumbers
            externalSearchText = request.phoneNumbers
                .sorted()
                .compactMap(PhoneNumber.formattedForDisplay)
                .joined(separator: ", ")
            searchText = externalSearchText ?? ""
            router.consumePatientSearchRequest(request.id)
        }
        .onChange(of: searchText) { _, newValue in
            guard let externalSearchText, newValue != externalSearchText else { return }
            externalPhoneNumbers = nil
            self.externalSearchText = nil
        }
    }

    private var patientDetailsList: [PatientDetails] {
        patientRows.map(\.details)
    }
}

#Preview {
    let database = try! prepareDependencies {
        let database = try appDatabase(seedSamples: true)
        $0.defaultDatabase = database
        return database
    }
    NavigationStack {
        PatientsView()
    }
    .environment(
        BackupCoordinator(
            database: database,
            store: BackupStateStore(
                directory: .temporaryDirectory.appending(path: UUID().uuidString)))
    )
    .environment(Router())
}
