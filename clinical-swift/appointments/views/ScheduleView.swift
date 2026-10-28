import ClinicalModels
import Dependencies
import SQLiteData
import SwiftUI

private let scheduleDayRadius = 3

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode. A session owns the active editor and its preview.
    /// This value controls the sheet, draft rendering, card interactions, and creation buttons.
    @State private var editorSession: ScheduleEditorSession?

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()
    #if DEBUG
        @State private var showsBookingPrototype = false
    #endif

    init() {
        scheduleModel = ScheduleModel()
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
                    items: visibleItems(for: date),
                    calendar: calendar,
                    needsBookingClearance: editorIsActive,
                    itemInteractionsEnabled: !editorIsActive,
                    scrollPosition: scrollPositionBinding(for: date),
                    onSelectItem: selectItem
                )
            }
        }
        .background(Color("AppBackground"))
        .navigationTitle(
            router.selectedScheduleDate.formatted(
                .dateTime
                    .weekday()
                    .month()
                    .day())
        )
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button("Booking prototype", systemImage: "sparkles") {
                        showsBookingPrototype = true
                    }
                }
            #endif
            ToolbarItem(placement: .topBarTrailing) {
                BackupSettingsButton()
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if !editorIsActive {
                    Button("Unavailable Time", systemImage: "nosign") {
                        router.requestUnavailableTimeCreation()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Display creation buttons only when no schedule editor is active.
                if !editorIsActive {
                    Button("Add", systemImage: "plus") {
                        router.requestAppointmentBooking()
                    }
                }
            }
        }
        #if DEBUG
            .navigationDestination(isPresented: $showsBookingPrototype) {
                BookingSnippetPlayground()
            }
        #endif
        .sheet(item: $editorSession, onDismiss: router.presentationDidDismiss) { session in
            ScheduleEditorSheet(session: session)
                .onAppear { router.presentationDidAppear(session.id) }
        }
        .task(id: scheduleEditorRequest?.id) {
            guard let request = scheduleEditorRequest else {
                editorSession = nil
                return
            }
            editorSession = ScheduleEditorSession(
                request: request, selectedDate: router.selectedScheduleDate,
                appointments: scheduleModel.appointments(for: router.selectedScheduleDate)
            ) { date in
                finishEditor(request.id, date: date)
            }
        }
        .task(id: editorSession?.id) {
            guard editorSession != nil else { return }

            // Let SwiftUI lay out the draft and sheet clearance before animating to its position.
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollToEditorPreview()
        }
        .task(id: visibleAppointmentDetailsScrollRequest) {
            scrollToVisibleAppointmentDetails()
        }
        // Update displayed appointments and re-calculate suggested slot for booking, if any
        .task(id: router.selectedScheduleDate) {
            let requestedDate = router.selectedScheduleDate
            do {
                try await scheduleModel.loadVisibleDays(
                    centeredOn: requestedDate,
                    dayRadius: scheduleDayRadius
                )

                // If date selection has changed after async load completion, stop here.
                guard !Task.isCancelled,
                    requestedDate.isSameDayAs(router.selectedScheduleDate)
                else {
                    return
                }

                scrollToVisibleAppointmentDetails()

                if editorSession?.updateAppointments(
                    scheduleModel.appointments(for: requestedDate), for: requestedDate
                ) == true {
                    scrollToEditorPreview()
                }
            } catch {
                return
            }
        }
        // Date, time, and duration changes can move the preview. Availability updates can also
        // move an appointment to a suggested slot. Keep the model's repeated scroll requests.
        .onChange(of: editorSession?.scrollRequest) { previous, current in
            // Initial presentation scrolls after layout in the session task above.
            guard let previous, let current, previous.sessionID == current.sessionID else { return }
            scrollToEditorPreview()
        }
    }

    private var selectedDateBinding: Binding<Date> {
        // The editor owns its draft date. Outside editing, mutate the router's app-level selection
        // so direct UI changes and external routing cannot diverge.
        Binding(
            get: { editorSession?.selectedDate ?? router.selectedScheduleDate },
            set: { selectDate($0) }
        )
    }

    private func selectDate(_ date: Date) {
        guard editorSession?.allowsDateSelection != false else { return }
        let selectedDate = date.startOfDay(using: calendar)
        router.selectScheduleDate(selectedDate)
        editorSession?.selectDate(selectedDate)
    }

    private var scheduleEditorRequest: AppPresentation? {
        // All schedule editors use the router's single active presentation and one sheet host.
        switch router.activePresentation {
        case .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
            router.activePresentation
        default:
            nil
        }
    }

    private var editorIsActive: Bool {
        scheduleEditorRequest != nil || editorSession != nil
    }

    private func visibleItems(for date: Date) -> [TimelineItem] {
        let items =
            scheduleModel.appointments(for: date).map(TimelineItem.appointment)
            + scheduleModel.unavailableTimes(for: date).map(TimelineItem.unavailableTime)
        return editorSession?.visibleItems(items, for: date) ?? items
    }

    private func timelineScale(for date: Date) -> TimelineScale {
        TimelineScale(items: visibleItems(for: date))
    }

    private var visibleAppointmentDetailsID: Appointment.ID? {
        guard
            let presentation = router.detailsPresentation,
            case .appointment(let id) = presentation.currentRoute
        else { return nil }

        return id
    }

    private var visibleAppointmentDetailsScrollRequest: AppointmentDetailsScrollRequest? {
        guard let visibleAppointmentDetailsID else { return nil }
        return AppointmentDetailsScrollRequest(
            appointmentID: visibleAppointmentDetailsID,
            selectedDate: router.selectedScheduleDate
        )
    }

    private func selectItem(_ item: TimelineItem) {
        switch item {
        case .appointment(let appointment):
            router.presentDetails(.appointment(appointment.id))
        case .unavailableTime(let block):
            router.requestUnavailableTimeEdit(block)
        }
    }

    private func finishEditor(_ requestID: UUID, date: Date) {
        guard let editorSession, editorSession.id == requestID,
            editorSession.finish(using: router, date: date)
        else { return }
        self.editorSession = nil
        Task {
            _ = try? await scheduleModel.loadVisibleDays(
                centeredOn: date,
                dayRadius: scheduleDayRadius
            )
        }
    }

    private func scrollToEditorPreview() {
        guard let preview = editorSession?.preview else { return }
        scrollToStart(preview.start)
    }

    private func scrollToVisibleAppointmentDetails() {
        guard
            let visibleAppointmentDetailsID,
            let appointment = scheduleModel.appointments(
                for: router.selectedScheduleDate
            ).first(where: { $0.id == visibleAppointmentDetailsID })
        else { return }

        scrollToStart(appointment.start)
    }

    private func scrollToStart(_ start: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollPosition.scrollTo(y: max(timelineScrollY(for: start), 0))
        }
    }

    private func timelineScrollY(for start: Date) -> CGFloat {
        timelineScale(for: router.selectedScheduleDate).yOffset(for: start.timeOfDay) - 80
    }

    private func scrollPositionBinding(for date: Date) -> Binding<ScrollPosition> {
        guard date.isSameDayAs(router.selectedScheduleDate) else {
            return .constant(ScrollPosition())
        }

        return $scrollPosition
    }
}

private struct AppointmentDetailsScrollRequest: Equatable {
    let appointmentID: Appointment.ID
    let selectedDate: Date
}

@MainActor
struct ScheduleEditorSession: Identifiable {
    let id: UUID
    let editor: Editor

    enum Editor {
        case appointment(AppointmentBookingModel)
        case unavailableTime(UnavailableTimeEditorModel)
    }

    init?(
        request: AppPresentation, selectedDate: Date, appointments: [Appointment],
        onFinished: @escaping (Date) -> Void
    ) {
        id = request.id
        switch request {
        case .appointmentBooking(let request):
            let model = AppointmentBookingModel(
                selectedDate: selectedDate, selectedPatient: request.patient, onSaved: onFinished)
            model.updateAppointments(appointments, for: selectedDate)
            model.prefillFirstAvailableSlot()
            // Install the model after prefilling slot - to ensure the sheet starts out displaying the
            // pre-selected slot rather than briefly showing the clinic opening time.
            editor = .appointment(model)
        case .appointmentEdit(let request):
            // Use the details that were already visible so the editor can start without another read.
            // Saving still validates the current stored appointment before writing.
            let model = AppointmentBookingModel(editing: request.details, onSaved: onFinished)
            model.updateAppointments(appointments, for: selectedDate)
            editor = .appointment(model)
        case .unavailableTimeEditor(let request):
            switch request.purpose {
            case .create:
                editor = .unavailableTime(
                    UnavailableTimeEditorModel(
                        id: request.id, selectedDate: selectedDate, onFinished: onFinished))
            case .edit(let block):
                editor = .unavailableTime(
                    UnavailableTimeEditorModel(
                        id: request.id, editing: block, onFinished: onFinished))
            }
        default:
            return nil
        }
    }

    var selectedDate: Date {
        switch editor {
        case .appointment(let model): model.selectedDate
        case .unavailableTime(let model): model.selectedDate
        }
    }

    var allowsDateSelection: Bool {
        switch editor {
        case .appointment: true
        case .unavailableTime(let model): !model.isWorking
        }
    }

    var preview: TimelineItem {
        switch editor {
        case .appointment(let model): .appointment(model.draftAppointment)
        case .unavailableTime(let model): .unavailableTime(model.preview)
        }
    }

    var scrollRequest: ScheduleEditorScrollRequest {
        let revision: Int
        switch editor {
        case .appointment(let model): revision = model.draftPreviewScrollRequest
        case .unavailableTime(let model): revision = model.draftPreviewScrollRequest
        }
        return ScheduleEditorScrollRequest(sessionID: id, date: selectedDate, revision: revision)
    }

    func selectDate(_ date: Date) {
        switch editor {
        case .appointment(let model): model.selectDate(date)
        case .unavailableTime(let model): model.selectDate(date)
        }
    }

    /// Only appointments use availability updates. Return whether the caller must reveal a draft.
    func updateAppointments(_ appointments: [Appointment], for date: Date) -> Bool {
        guard case .appointment(let model) = editor else { return false }
        model.updateAppointments(appointments, for: date)
        return true
    }

    func visibleItems(_ items: [TimelineItem], for date: Date) -> [TimelineItem] {
        @Dependency(\.calendar) var calendar
        let editedID: TimelineItem.ID?
        switch editor {
        case .appointment(let model):
            // Keep the saved appointment visible on other pages until the edit is saved.
            guard calendar.isDate(selectedDate, inSameDayAs: date) else { return items }
            editedID = model.purpose.editedAppointmentID.map { .appointment($0) }
        case .unavailableTime(let model):
            editedID = model.purpose.editedID.map { .unavailableTime($0) }
        }
        var items = items.filter { $0.id != editedID }
        let preview = preview
        if calendar.isDate(preview.start, inSameDayAs: date) {
            items.append(preview)
        }
        return items
    }

    func finish(using router: Router, date: Date) -> Bool {
        // A late save must not close a newer presentation or change its date.
        guard router.activePresentation?.id == id else { return false }
        router.finishScheduleEditor(id, date: date)
        return true
    }
}

nonisolated struct ScheduleEditorScrollRequest: Equatable {
    let sessionID: UUID
    let date: Date
    let revision: Int
}

private struct ScheduleEditorSheet: View {
    let session: ScheduleEditorSession

    var body: some View {
        switch session.editor {
        case .appointment(let model): AppointmentBookingView(model: model)
        case .unavailableTime(let model): UnavailableTimeEditorView(model: model)
        }
    }
}

private struct ScheduleTimelinePage: View {
    let date: Date
    let items: [TimelineItem]
    let calendar: Calendar
    let needsBookingClearance: Bool
    let itemInteractionsEnabled: Bool
    @Binding var scrollPosition: ScrollPosition
    let onSelectItem: (TimelineItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Timeline(
                    items: items,
                    scale: TimelineScale(items: items),
                    showsNowMarker: calendar.isDateInToday(date),
                    itemInteractionsEnabled: itemInteractionsEnabled,
                    onSelectItem: onSelectItem
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
    let database = try! prepareDependencies {
        let database = try appDatabase(seedSamples: true)
        $0.defaultDatabase = database
        return database
    }
    NavigationStack {
        ScheduleView()
    }
    .environment(
        BackupCoordinator(
            database: database,
            store: BackupStateStore(
                directory: .temporaryDirectory.appending(path: UUID().uuidString)))
    )
    .environment(Router())
}
