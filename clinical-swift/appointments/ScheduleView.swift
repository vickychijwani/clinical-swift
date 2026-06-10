import SwiftUI

struct ScheduleView: View {
    @Binding var selectedDate: Date

    var body: some View {
        ScrollView {
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
        }
        .background(Color("AppBackground"))
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(selectedDate.formatted(
            .dateTime
                .weekday()
                .month()
                .day()
                .year()))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {}
            }
        }
    }
}

#Preview {
    ScheduleView(selectedDate: .constant(.now))
}
