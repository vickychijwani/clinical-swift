import SQLiteData
import SwiftUI

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode; non-nil means booking mode.
    /// This value controls booking sheet presentation, rendering of draft appointment in the
    /// timeline, whether appointment cards are interactable, and whether '+' button appears.
    @State private var bookingModel: AppointmentBookingModel?

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()
    @State private var compactBookingSheetHeight =
        AppointmentBookingSheetMetrics.fallbackCompactDetentHeight

    init() {
        scheduleModel = ScheduleModel(selectedDate: Date.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekDateStrip(selectedDate: selectedDateBinding)

            ScrollView {
                VStack(spacing: 0) {
                    Timeline(
                        appointments: visibleAppointments,
                        scale: timelineScale,
                        showsNowMarker: calendar.isDateInToday(scheduleModel.selectedDate),
                        appointmentInteractionsEnabled: bookingModel == nil,
                        onSelectAppointment: selectAppointment
                    )

                    Color.clear
                        .frame(height: bottomScrollClearance)
                }
            }
            .modifier(TimelineScrollModifier(scrollPosition: $scrollPosition))
        }
        .background(Color("AppBackground"))
        .navigationTitle(
            scheduleModel.selectedDate.formatted(
                .dateTime
                    .weekday()
                    .month()
                    .day()
                    .year())
        )
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Display '+' button only if we're not already booking an appointment
                if bookingModel == nil {
                    Button("Add", systemImage: "plus") {
                        startBooking()
                    }
                }
            }
        }
        .sheet(item: $bookingModel) { bookingModel in
            NavigationStack {
                AppointmentBookingView(
                    model: bookingModel,
                    compactSheetHeight: $compactBookingSheetHeight
                )
            }
        }
        // Update displayed appointments and re-calculate suggested slot for booking, if any
        .task(id: scheduleModel.selectedDate) {
            let requestedDate = scheduleModel.selectedDate
            do {
                try await scheduleModel.load()

                // If date selection has changed after async load completion, stop here.
                guard !Task.isCancelled,
                    requestedDate.isSameDayAs(scheduleModel.selectedDate)
                else {
                    return
                }

                bookingModel?.updateAppointments(
                    scheduleModel.appointments,
                    for: requestedDate
                )
            } catch {
                return
            }
        }
        // Auto-scroll to show draft booking on date/time/duration changes.
        // Why on duration changes? Because change of duration might change suggested slot and move
        // the draft automatically.
        .onChange(of: activeBookingDate) {
            scrollToDraftAppointment()
        }
        .onChange(of: draftPreviewScrollRequest) {
            scrollToDraftAppointment()
        }
    }

    /// Switch to booking mode - create a model, select a slot based on existing appointments, and
    /// scroll to preview.
    private func startBooking() {
        let bookingModel = AppointmentBookingModel(selectedDate: scheduleModel.selectedDate) {
            bookedDate in
            refreshAppointments(for: bookedDate)
        }
        bookingModel.updateAppointments(
            scheduleModel.appointments,
            for: scheduleModel.selectedDate
        )
        bookingModel.prefillFirstAvailableSlot()

        // Install the model after prefilling slot - to ensure the sheet starts out displaying the
        // pre-selected slot rather than briefly showing the clinic opening time.
        self.bookingModel = bookingModel
        scrollToDraftAppointment()
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: {
                bookingModel?.selectedDate ?? scheduleModel.selectedDate
            },
            set: { newDate in
                selectDate(newDate)
            }
        )
    }

    private func selectDate(_ date: Date) {
        let selectedDate = date.startOfDay(using: calendar)
        scheduleModel.selectedDate = selectedDate
        bookingModel?.selectDate(selectedDate)
    }

    private var activeBookingDate: Date? {
        bookingModel?.selectedDate
    }

    private var draftPreviewScrollRequest: Int {
        bookingModel?.draftPreviewScrollRequest ?? 0
    }

    private var visibleAppointments: [Appointment] {
        guard let bookingModel else {
            return scheduleModel.appointments
        }

        return scheduleModel.appointments + [bookingModel.draftAppointment]
    }

    private var timelineScale: TimelineScale {
        TimelineScale(appointments: visibleAppointments)
    }

    private func selectAppointment(_ appointment: Appointment) {
        router.presentDetails(.appointment(appointment.id))
    }

    private var bottomScrollClearance: CGFloat {
        bookingModel == nil ? 0 : compactBookingSheetHeight
    }

    private func refreshAppointments(for date: Date) {
        scheduleModel.selectedDate = date.startOfDay(using: calendar)
        bookingModel = nil
        Task {
            _ = try? await scheduleModel.load()
        }
    }

    private func scrollToDraftAppointment() {
        guard let bookingModel else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            scrollPosition.scrollTo(y: max(bookingScrollY(for: bookingModel.draft.start), 0))
        }
    }

    private func bookingScrollY(for start: Date) -> CGFloat {
        timelineScale.yOffset(for: start.timeOfDay) - 80
    }
}

private struct TimelineScrollModifier: ViewModifier {
    @Binding var scrollPosition: ScrollPosition
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 1
            } action: { _, isScrolled in
                self.isScrolled = isScrolled
            }
            .overlay(alignment: .top) {
                if isScrolled {
                    TimelineTopScrollFade()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isScrolled)
    }
}

private struct TimelineTopScrollFade: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color("AppBackground"),
                Color("AppBackground").opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 20)
        .allowsHitTesting(false)
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
