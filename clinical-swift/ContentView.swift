import SwiftUI

struct ContentView: View {
    @State private var selectedDate = Date.now.startOfDay()

    var body: some View {
        TabView {
            Tab("Schedule", systemImage: "calendar") {
                NavigationStack {
                    ScheduleView(selectedDate: $selectedDate)
                }
            }

            Tab("Patients", systemImage: "person.2") {
                NavigationStack {
                    PatientsView(patients: samplePatients)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
