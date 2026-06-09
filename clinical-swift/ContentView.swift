import SwiftUI

struct ContentView: View {
    @State private var selectedDate = Date.now.startOfDay()

    var body: some View {
        VStack(spacing: 0) {
            WeekDateStrip(selectedDate: $selectedDate)

            Timeline(
                appointments: sampleAppointments,
                startTime: Bitehaus.startTime,
                endTime: Bitehaus.closingTime,
                breakBlock: Bitehaus.breakBlock,
                showsNowMarker: false
            )
        }
        .background(Color("AppBackground"))
    }
}

#Preview {
    ContentView()
}
