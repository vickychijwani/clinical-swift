import SQLiteData
import SwiftUI

struct ContentView: View {
    @State private var router = Router()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Schedule", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack(path: $router.schedulePath) {
                    ScheduleView()
                }
            }

            Tab("Patients", systemImage: "person.2", value: AppTab.patients) {
                NavigationStack(path: $router.patientsPath) {
                    PatientsView()
                }
            }
        }
        .sheet(
            item: $router.detailsPresentation,
            onDismiss: router.detailsDidDismiss
        ) { presentation in
            DetailsFlowSheet(presentation: presentation)
                .id(presentation.id)
        }
        .sheet(
            item: patientEditRequestBinding,
            onDismiss: router.patientEditorDidDismiss
        ) { request in
            EditPatientView(patient: request.patient)
        }
        .environment(router)
    }

    private var patientEditRequestBinding: Binding<PatientEditRequest?> {
        Binding(
            get: { router.patientEditRequest },
            set: { newValue in
                guard newValue == nil, let requestID = router.patientEditRequest?.id else {
                    return
                }
                router.consumePatientEditRequest(requestID)
            }
        )
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    ContentView()
}
