import SQLiteData
import SwiftUI

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar

    @State private var isBookingAppointment = false
    @State private var model: ScheduleModel

    init() {
        model = ScheduleModel(selectedDate: Date.now)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                WeekDateStrip(selectedDate: $model.selectedDate)

                Timeline(
                    appointments: model.appointments,
                    startTime: Bitehaus.opening,
                    endTime: Bitehaus.closing,
                    breakBlock: Bitehaus.break,
                    showsNowMarker: calendar.isDateInToday(model.selectedDate)
                )
            }
        }
        .background(Color("AppBackground"))
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(model.selectedDate.formatted(
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
                AppointmentBookingView(selectedDate: model.selectedDate) { bookedDate in
                    model.selectedDate = bookedDate.startOfDay()
                    refreshAppointments(for: bookedDate)
                }
            }
        }
        .task(id: model.selectedDate) {
            _ = try? await model.load()
        }
    }

    private func refreshAppointments(for date: Date) {
        model.selectedDate = date
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase(seedSamples: true)
    }
    NavigationStack {
        ScheduleView()
    }
}
