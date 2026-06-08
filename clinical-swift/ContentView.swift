import SwiftUI

struct ContentView: View {
    var body: some View {
        Timeline(
            appointments: sampleAppointments,
            startTime: Bitehaus.startTime,
            endTime: Bitehaus.closingTime,
            breakBlock: Bitehaus.breakBlock,
            showsNowMarker: false
        )
    }
}

#Preview {
    ContentView()
}
