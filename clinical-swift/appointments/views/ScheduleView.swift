import Dependencies
import SQLiteData
import SwiftUI

private let scheduleDayRadius = 3

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode; non-nil means booking mode.
    /// This value controls booking sheet presentation, rendering of draft appointment in the
    /// timeline, whether appointment cards are interactable, and whether '+' button appears.
    @State private var bookingModel: AppointmentBookingModel?

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()

    init() {
        scheduleModel = ScheduleModel(selectedDate: Date.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekDateStrip(selectedDate: selectedDateBinding)

            CalendarDayPager(
                selectedDate: selectedDateBinding,
                calendar: calendar,
                dayRadius: scheduleDayRadius
            ) { date in
                ScheduleTimelinePage(
                    date: date,
                    appointments: visibleAppointments(for: date),
                    calendar: calendar,
                    needsBookingClearance: bookingModel != nil,
                    appointmentInteractionsEnabled: bookingModel == nil,
                    scrollPosition: scrollPositionBinding(for: date),
                    onSelectAppointment: selectAppointment
                )
            }
        }
        .background(Color("AppBackground"))
        .navigationTitle(
            scheduleModel.selectedDate.formatted(
                .dateTime
                    .weekday()
                    .month()
                    .day())
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
        .sheet(
            item: $bookingModel,
            onDismiss: router.appointmentEditorDidDismiss
        ) { bookingModel in
            AppointmentBookingView(model: bookingModel)
        }
        .task(id: router.appointmentEditRequest?.id) {
            guard let request = router.appointmentEditRequest else { return }
            startEditing(request)
        }
        .task(id: router.appointmentBookingRequest?.id) {
            guard let request = router.appointmentBookingRequest else { return }
            startBooking(request)
        }
        .task(id: router.scheduleDateRequest?.id) {
            guard let request = router.scheduleDateRequest else { return }
            if let date = request.day.date(using: calendar) {
                scheduleModel.selectedDate = date
            }
            router.consumeScheduleDateRequest(request.id)
        }
        .task(id: bookingModel?.id) {
            guard bookingModel != nil else { return }

            // Let SwiftUI lay out the draft and sheet clearance before animating to its position.
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToDraftAppointment()
        }
        .task(id: visibleAppointmentDetailsID) {
            guard
                let visibleAppointmentDetailsID,
                let appointment = scheduleModel.appointments.first(where: {
                    $0.id == visibleAppointmentDetailsID
                })
            else { return }

            scrollToAppointment(appointment)
        }
        // Update displayed appointments and re-calculate suggested slot for booking, if any
        .task(id: scheduleModel.selectedDate) {
            let requestedDate = scheduleModel.selectedDate
            do {
                try await scheduleModel.loadVisibleDays(
                    centeredOn: requestedDate,
                    dayRadius: scheduleDayRadius
                )

                // If date selection has changed after async load completion, stop here.
                guard !Task.isCancelled,
                    requestedDate.isSameDayAs(scheduleModel.selectedDate)
                else {
                    return
                }

                if let bookingModel {
                    bookingModel.updateAppointments(
                        scheduleModel.appointments(for: requestedDate),
                        for: requestedDate
                    )
                    scrollToDraftAppointment()
                }
            } catch {
                return
            }
        }
        // Auto-scroll to show draft booking on date/time/duration changes.
        // Why on duration changes? Because change of duration might change suggested slot and move
        // the draft automatically.
        .onChange(of: activeBookingDate) { previousDate, _ in
            // Initial presentation scrolls after layout in the booking-model task above.
            guard previousDate != nil else { return }
            scrollToDraftAppointment()
        }
        .onChange(of: draftPreviewScrollRequest) {
            scrollToDraftAppointment()
        }
    }

    /// Switch to booking mode and select a slot based on existing appointments. Installing the
    /// model triggers the layout-aware preview scroll above.
    private func startBooking(selectedPatient: Patient? = nil) {
        let bookingModel = AppointmentBookingModel(
            selectedDate: scheduleModel.selectedDate,
            selectedPatient: selectedPatient
        ) { bookedDate in
            refreshAppointments(for: bookedDate)
        }
        bookingModel.updateAppointments(
            scheduleModel.appointments(for: scheduleModel.selectedDate),
            for: scheduleModel.selectedDate
        )
        bookingModel.prefillFirstAvailableSlot()

        // Install the model after prefilling slot - to ensure the sheet starts out displaying the
        // pre-selected slot rather than briefly showing the clinic opening time.
        self.bookingModel = bookingModel
    }

    private func startBooking(_ request: AppointmentBookingRequest) {
        guard router.appointmentBookingRequest?.id == request.id else { return }
        startBooking(selectedPatient: request.patient)
        router.consumeAppointmentBookingRequest(request.id)
    }

    private func startEditing(_ request: AppointmentEditRequest) {
        guard router.appointmentEditRequest?.id == request.id else { return }

        // Use the details that were already visible so the editor can start without another read.
        // Saving still validates the current stored appointment before writing.
        let details = request.details
        let wasShowingAppointmentDate = details.appointment.start.isSameDayAs(
            scheduleModel.selectedDate
        )
        scheduleModel.selectedDate = details.appointment.start.startOfDay(using: calendar)

        let bookingModel = AppointmentBookingModel(editing: details) { savedDate in
            refreshAppointments(for: savedDate)
        }
        // If the date changed, these appointments still belong to the previous day. The
        // date-keyed load task will update the booking model after loading the correct day.
        if wasShowingAppointmentDate {
            bookingModel.updateAppointments(
                scheduleModel.appointments(for: scheduleModel.selectedDate),
                for: scheduleModel.selectedDate
            )
        }

        self.bookingModel = bookingModel
        router.consumeAppointmentEditRequest(request.id)
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

    private func visibleAppointments(for date: Date) -> [Appointment] {
        let appointments = scheduleModel.appointments(for: date)
        guard
            let bookingModel,
            bookingModel.selectedDate.isSameDayAs(date)
        else {
            return appointments
        }

        let visibleAppointments = appointments.filter {
            $0.id != bookingModel.purpose.editedAppointmentID
        }
        return visibleAppointments + [bookingModel.draftAppointment]
    }

    private func timelineScale(for date: Date) -> TimelineScale {
        TimelineScale(appointments: visibleAppointments(for: date))
    }

    private var visibleAppointmentDetailsID: Appointment.ID? {
        guard
            let presentation = router.detailsPresentation,
            case .appointment(let id) = presentation.currentRoute
        else { return nil }

        return id
    }

    private func selectAppointment(_ appointment: Appointment) {
        router.presentDetails(.appointment(appointment.id))
    }

    private func refreshAppointments(for date: Date) {
        scheduleModel.selectedDate = date.startOfDay(using: calendar)
        bookingModel = nil
        Task {
            _ = try? await scheduleModel.loadVisibleDays(
                centeredOn: date,
                dayRadius: scheduleDayRadius
            )
        }
    }

    private func scrollToDraftAppointment() {
        guard let bookingModel else {
            return
        }

        scrollToAppointment(bookingModel.draftAppointment)
    }

    private func scrollToAppointment(_ appointment: Appointment) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollPosition.scrollTo(y: max(timelineScrollY(for: appointment.start), 0))
        }
    }

    private func timelineScrollY(for start: Date) -> CGFloat {
        timelineScale(for: scheduleModel.selectedDate).yOffset(for: start.timeOfDay) - 80
    }

    private func scrollPositionBinding(for date: Date) -> Binding<ScrollPosition> {
        guard date.isSameDayAs(scheduleModel.selectedDate) else {
            return .constant(ScrollPosition())
        }

        return $scrollPosition
    }
}

private struct ScheduleTimelinePage: View {
    let date: Date
    let appointments: [Appointment]
    let calendar: Calendar
    let needsBookingClearance: Bool
    let appointmentInteractionsEnabled: Bool
    @Binding var scrollPosition: ScrollPosition
    let onSelectAppointment: (Appointment) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Timeline(
                    appointments: appointments,
                    scale: TimelineScale(appointments: appointments),
                    showsNowMarker: calendar.isDateInToday(date),
                    appointmentInteractionsEnabled: appointmentInteractionsEnabled,
                    onSelectAppointment: onSelectAppointment
                )

                if needsBookingClearance {
                    // Leave room to scroll late appointments above the booking sheet.
                    Color.clear
                        .containerRelativeFrame(
                            .vertical,
                            count: 2,
                            span: 1,
                            spacing: 0
                        )
                }
            }
        }
        .modifier(TimelineScrollModifier(scrollPosition: $scrollPosition))
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
