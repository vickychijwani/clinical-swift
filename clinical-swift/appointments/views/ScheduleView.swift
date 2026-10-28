import ClinicalModels
import Dependencies
import SQLiteData
import SwiftUI

private let scheduleDayRadius = 3

struct ScheduleView: View {
    @Dependency(\.calendar) private var calendar
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode. A session owns the editor and its draft preview.
    /// This value controls the sheet, draft rendering, card interactions, and creation buttons.
    @State private var editorSession: ScheduleEditorSession?

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()

    private var editorSheet: Binding<ScheduleEditorSession?> {
        Binding(
            get: {
                guard editorSession?.isShowingSheet == true else { return nil }
                return editorSession
            },
            set: { value in
                editorSession?.isShowingSheet = value != nil
            })
    }

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
                    itemInteractionsEnabled: !hasEditor,
                    scrollPosition: scrollPositionBinding(for: date),
                    onSelectItem: selectItem,
                    onSelectDraft: { editorSession?.isShowingSheet = true },
                    allowsAdjustment: editorSession.map {
                        $0.allowsDateSelection && !$0.isShowingSheet
                    }
                        ?? !hasEditor,
                    editorSession: editorSession,
                    isWorking: editorSession?.isWorking == true,
                    onBeginBooking: { beginBooking(center: $0, on: date) },
                    onBookingRelease: { released in
                        editorSession?.releaseBooking(released)
                    },
                    onCancel: { editorSession?.adjustment.release() },
                    onDiscard: {
                        if let editorSession {
                            finishEditor(editorSession.id, date: router.selectedScheduleDate)
                        }
                    },
                    onDone: { await editorSession?.save() },
                    onDelete: editorSession?.canDelete == true ? deleteEditor : nil
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
        .toolbar(editorSession != nil ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if editorSession == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    BackupSettingsButton()
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    if !hasEditor {
                        Button("Unavailable Time", systemImage: "nosign") {
                            router.requestUnavailableTimeCreation()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Display creation buttons only when there is no schedule editor.
                    if !hasEditor {
                        Button("Add", systemImage: "plus") {
                            router.requestAppointmentBooking()
                        }
                    }
                }
            }
        }
        .alert(
            editorSession?.errorTitle ?? "Unable to save",
            isPresented: Binding(
                get: { editorSession?.errorMessage != nil },
                set: { if !$0 { editorSession?.errorMessage = nil } }
            )
        ) {
            Button("OK") { editorSession?.errorMessage = nil }
        } message: {
            Text(editorSession?.errorMessage ?? "")
        }
        .sheet(
            item: editorSheet,
            onDismiss: {
                router.presentationDidDismiss(
                    retainingScheduleEditor: editorSession?.id)
            }
        ) { session in
            ScheduleEditorSheet(session: session)
                .onAppear { router.presentationDidAppear(session.id) }
        }
        .task(id: scheduleEditorRequest?.id) {
            guard let request = scheduleEditorRequest else {
                editorSession = nil
                return
            }
            // A timeline hold installs its session before the first drag update.
            guard editorSession?.id != request.id else { return }
            editorSession = ScheduleEditorSession(
                request: request, selectedDate: router.selectedScheduleDate,
                appointments: scheduleModel.appointments(for: router.selectedScheduleDate)
            ) { date in
                finishEditor(request.id, date: date)
            }
        }
        .task(id: editorSession?.id) {
            guard let editorSession, !editorSession.adjustment.isDragging else { return }

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
        .timelineTuningOverlay(isVisible: showsCardLab)
    }

    private var showsCardLab: Bool {
        guard router.selectedTab == .schedule, router.schedulePath.isEmpty,
            editorSheet.wrappedValue == nil
        else { return false }
        switch router.activePresentation {
        case nil:
            return true
        case .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
            return editorSession?.isShowingSheet == false
        default:
            return false
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
        guard editorSession?.allowsDateSelection != false,
            editorSession?.adjustment.isDragging != true
        else { return }
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

    private var hasEditor: Bool {
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
        guard !hasEditor else { return }
        switch item {
        case .appointment(let appointment):
            router.presentDetails(.appointment(appointment.id))
        case .unavailableTime(let block):
            router.requestUnavailableTimeEdit(block)
        }
    }

    private func beginBooking(center: TimeOfDay, on date: Date) -> ScheduleEditorSession? {
        guard !hasEditor,
            date.isSameDayAs(router.selectedScheduleDate)
        else { return nil }
        router.requestAppointmentBooking()
        guard let request = scheduleEditorRequest else { return nil }
        editorSession = ScheduleEditorSession(
            bookingID: request.id, selectedDate: date, center: center,
            items: visibleItems(for: date)
        ) { savedDate in
            finishEditor(request.id, date: savedDate)
        }
        return editorSession
    }

    private func deleteEditor() async {
        await editorSession?.delete()
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

private struct ScheduleEditorSheet: View {
    let session: ScheduleEditorSession

    var body: some View {
        switch session.editor {
        case .appointment(let model): AppointmentBookingView(model: model)
        case .unavailableTime(let model): UnavailableTimeEditorView(model: model)
        }
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
