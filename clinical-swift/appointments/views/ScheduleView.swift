import SQLiteData
import SwiftUI

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar
    @Dependency(\.defaultDatabase) private var database
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode; non-nil means booking mode.
    /// This value controls booking sheet presentation, rendering of draft appointment in the
    /// timeline, whether appointment cards are interactable, and whether '+' button appears.
    @State private var bookingModel: AppointmentBookingModel?

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()
    @State private var editErrorMessage: String?

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

                    if needsSheetClearance {
                        // Leave room to scroll late appointments above an interactable sheet.
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
            AppointmentBookingView(model: bookingModel)
        }
        .alert(
            "Unable to edit appointment",
            isPresented: Binding(
                get: { editErrorMessage != nil },
                set: { if !$0 { editErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                editErrorMessage = nil
            }
        } message: {
            Text(editErrorMessage ?? "")
        }
        .task(id: router.appointmentEditRequest?.id) {
            guard let request = router.appointmentEditRequest else { return }
            await startEditing(request)
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

            // Let SwiftUI add sheet clearance before scrolling the selected appointment into view.
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToAppointment(appointment)
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

                if let bookingModel {
                    bookingModel.updateAppointments(
                        scheduleModel.appointments,
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
    }

    private func startEditing(_ request: AppointmentEditRequest) async {
        do {
            let row = try await database.read { db in
                try appointmentDetailsQuery(id: request.appointmentID).fetchOne(db)
            }
            guard
                let details = row?.details,
                details.appointment.status == .scheduled
            else {
                failEditing(request)
                return
            }

            // Do not consume in a defer or in the caller. A cancelled task or stale request has not
            // been handled; leaving it active lets the current ScheduleView process it later.
            guard !Task.isCancelled,
                router.appointmentEditRequest?.id == request.id
            else { return }

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
                    scheduleModel.appointments,
                    for: scheduleModel.selectedDate
                )
            }

            self.bookingModel = bookingModel
            router.consumeAppointmentEditRequest(request.id)
        } catch is CancellationError {
            return
        } catch {
            failEditing(request)
        }
    }

    private func failEditing(_ request: AppointmentEditRequest) {
        guard router.appointmentEditRequest?.id == request.id else { return }
        router.consumeAppointmentEditRequest(request.id)
        editErrorMessage = "This appointment is unavailable or is no longer scheduled."
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

        let appointments = scheduleModel.appointments.filter {
            $0.id != bookingModel.purpose.editedAppointmentID
        }
        return appointments + [bookingModel.draftAppointment]
    }

    private var timelineScale: TimelineScale {
        TimelineScale(appointments: visibleAppointments)
    }

    private var needsSheetClearance: Bool {
        bookingModel != nil
            || (router.selectedTab == .schedule && router.detailsPresentation != nil)
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
            _ = try? await scheduleModel.load()
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
