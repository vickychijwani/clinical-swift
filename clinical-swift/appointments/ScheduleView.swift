import SQLiteData
import SwiftUI

struct ScheduleView: View {
    @Binding var selectedDate: Date

    @FetchAll(scheduleAppointmentsQuery(selectedDate: .now), animation: .default)
    private var appointmentRows: [ScheduleAppointmentRow]

    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        self._appointmentRows = FetchAll(
            scheduleAppointmentsQuery(selectedDate: selectedDate.wrappedValue),
            animation: .default
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                WeekDateStrip(selectedDate: $selectedDate)

                Timeline(
                    appointments: appointments,
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
        .task(id: selectedDate) {
            _ = try? await $appointmentRows.load(
                scheduleAppointmentsQuery(selectedDate: selectedDate),
                animation: .default
            )
        }
    }

    private var appointments: [Appointment] {
        appointmentRows.compactMap(\.appointment)
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    ScheduleView(selectedDate: .constant(.now))
}
