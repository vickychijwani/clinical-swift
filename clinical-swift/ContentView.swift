import SwiftUI

struct ContentView: View {
    @State private var router = Router()
    @State private var selectedDate = Date.now.startOfDay()

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.schedulePath) {
                ScheduleView(selectedDate: $selectedDate)
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }
            .tag(AppTab.schedule)

            NavigationStack(path: $router.patientsPath) {
                PatientsView(patients: samplePatients)
            }
            .tabItem {
                Label("Patients", systemImage: "person.2")
            }
            .tag(AppTab.patients)
        }
        .environment(router)
    }
}

#Preview {
    ContentView()
}
