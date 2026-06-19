import SQLiteData
import SwiftUI

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar

    @Binding var selectedDate: Date
    @State private var isBookingAppointment = false

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
                    startTime: Bitehaus.opening,
                    endTime: Bitehaus.closing,
                    breakBlock: Bitehaus.break,
                    showsNowMarker: calendar.isDateInToday(selectedDate)
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
                Button("Add", systemImage: "plus") {
                    isBookingAppointment = true
                }
            }
        }
        .sheet(isPresented: $isBookingAppointment) {
            NavigationStack {
                AppointmentBookingView(selectedDate: selectedDate) { bookedDate in
                    selectedDate = bookedDate.startOfDay()
                    refreshAppointments(for: bookedDate)
                }
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

    private func refreshAppointments(for date: Date) {
        Task {
            _ = try? await $appointmentRows.load(
                scheduleAppointmentsQuery(selectedDate: date),
                animation: .default
            )
        }
    }
}

#Preview {
    @Previewable @State var selectedDate: Date = .now

    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    ScheduleView(selectedDate: $selectedDate)
}
