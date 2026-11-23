import ClinicalModels
import Dependencies
import SQLiteData
import SwiftUI

private let scheduleDayRadius = 3

struct ScheduleView: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.clinicToday) private var clinicToday
    @Environment(Router.self) private var router

    /// `nil` means normal schedule mode. A session owns the editor and its draft preview.
    /// This value controls the sheet, draft rendering, card interactions, and creation buttons.
    @Environment(ScheduleEditorStore.self) private var editor
    private var editorSession: ScheduleEditorSession? {
        get { editor.session }
        nonmutating set { editor.session = newValue }
    }

    @State private var scheduleModel: ScheduleModel
    @State private var scrollPosition = ScrollPosition()

    init() {
        scheduleModel = ScheduleModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekDateStrip(selectedDate: selectedDateBinding, today: clinicToday)

            CalendarDayPager(
                selectedDate: selectedDateBinding,
                calendar: ClinicDate.calendar,
                dayRadius: scheduleDayRadius,
                isPagingEnabled: editorSession?.allowsDateSelection != false
                    && editorSession?.adjustment.isDragging != true
            ) { date in
                ScheduleTimelinePage(
                    date: date,
                    today: clinicToday,
                    items: visibleItems(for: date),
                    itemInteractionsEnabled: !hasEditor,
                    selectedAppointmentID: selectedAppointmentID,
                    scrollPosition: scrollPositionBinding(for: date),
                    onSelectItem: selectItem,
                    onSelectDraft: { editorSession?.isShowingSheet = true },
                    allowsAdjustment: editorSession.map {
                        $0.allowsDateSelection && !$0.isShowingSheet
                    }
                        ?? !hasEditor,
                    editorSession: editorSession,
                    isWorking: editorSession?.isWorking == true,
                    onBeginHold: { beginHold(on: $0, center: $1, date: date) },
                    onHoldRelease: { released in
                        if editorSession?.allowsTypeSelection == true {
                            editorSession?.releaseBooking(released)
                        }
                    },
                    onCancel: { editorSession?.adjustment.release() },
                    onDiscard: {
                        if let editorSession {
                            finishEditor(
                                editorSession.id,
                                completion: .discarded(date: router.selectedScheduleDate)
                            )
                        }
                    },
                    onDone: { await editorSession?.save() },
                    onDelete: editorSession?.canDelete == true ? deleteEditor : nil
                )
            }
            .accessibilityIdentifier("schedule-day-pager")
        }
        .background(palette[.canvas])
        .navigationTitle(
            router.selectedScheduleDate.formatted(
                ClinicDate.formatStyle
                    .weekday()
                    .month()
                    .day())
        )
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(palette[.canvas], for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(editorSession != nil ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if !hasEditor {
                BackupWarningToolbar(showsTrailingSpacer: true)
                ToolbarItem(placement: .topBarTrailing) {
                    // Display the creation button only when there is no schedule editor.
                    Button("Add", systemImage: "plus") {
                        router.requestScheduleCreation()
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
        .task(id: scheduleEditorLoadKey) {
            await editor.prepare(
                request: scheduleEditorRequest,
                router: router,
                appointmentsForBooking: { await scheduleModel.appointmentsForBooking(on: $0) },
                onFinished: finishEditor
            )
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
        // Load the visible days without changing the doctor's chosen draft interval.
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

                if editorSession != nil {
                    scrollToEditorPreview()
                }
            } catch {
                return
            }
        }
        // Date and type changes can move the preview. Keep the session's repeated scroll requests.
        .onChange(of: editorSession?.scrollRequest) { previous, current in
            // Initial presentation scrolls after layout in the session task above.
            guard let previous, let current, previous.sessionID == current.sessionID else { return }
            scrollToEditorPreview()
        }
        .timelineTuningOverlay(isVisible: showsDesignLabs)
        .colorLabOverlay(isVisible: showsDesignLabs)
    }

    private var showsDesignLabs: Bool {
        guard router.selectedTab == .schedule, router.schedulePath.isEmpty
        else { return false }
        switch router.activePresentation {
        case nil:
            return true
        case .scheduleCreation, .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
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
        let selectedDate = ClinicDate.day(date)
        router.selectScheduleDate(selectedDate)
        editorSession?.selectDate(selectedDate)
    }

    private var scheduleEditorRequest: AppPresentation? {
        // All schedule editors use the router's single active presentation and one sheet host.
        switch router.activePresentation {
        case .scheduleCreation, .appointmentBooking, .appointmentEdit, .unavailableTimeEditor:
            router.activePresentation
        default:
            nil
        }
    }

    private var scheduleEditorLoadKey: ScheduleEditorLoadKey? {
        scheduleEditorRequest.map {
            ScheduleEditorLoadKey(requestID: $0.id, date: router.selectedScheduleDate)
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

    private var selectedAppointmentID: Appointment.ID? {
        Self.selectedAppointmentID(for: router, hasEditor: editorSession != nil)
    }

    static func selectedAppointmentID(for router: Router, hasEditor: Bool) -> Appointment.ID? {
        guard router.selectedTab == .schedule,
            router.schedulePath.isEmpty,
            !hasEditor,
            let presentation = router.detailsPresentation
        else { return nil }
        switch presentation.currentRoute {
        case .appointment(let id):
            return id
        case .appointmentCompletion(let visitID):
            return presentation.completionDrafts[visitID]?.appointmentID
        case .patient:
            return nil
        }
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

    private func beginHold(
        on item: TimelineItem?, center: TimeOfDay, date: Date
    ) -> ScheduleEditorSession? {
        guard !hasEditor,
            date.isSameDayAs(router.selectedScheduleDate)
        else { return nil }
        if let item {
            guard item.allowsAdjustment else { return nil }
            switch item {
            case .appointment(let appointment):
                guard let details = scheduleModel.details(for: appointment),
                    details.appointment.status == .scheduled
                else { return nil }
                router.requestAppointmentEdit(details)
            case .unavailableTime(let block):
                router.requestUnavailableTimeEdit(block)
            }
            guard let request = scheduleEditorRequest,
                let session = ScheduleEditorSession(
                    request: request, selectedDate: date, appointments: [],
                    onFinished: { finishEditor(request.id, completion: $0) })
            else { return nil }
            session.beginAdjustment(item, edge: .move, items: visibleItems(for: date))
            editorSession = session
            return session
        }
        router.requestScheduleCreation()
        guard let request = router.scheduleCreationRequest else { return nil }
        editorSession = ScheduleEditorSession(
            bookingID: request.id, selectedDate: date, center: center,
            items: visibleItems(for: date)
        ) { completion in
            finishEditor(request.id, completion: completion)
        }
        return editorSession
    }

    private func deleteEditor() async {
        await editorSession?.delete()
    }

    private func finishEditor(_ requestID: UUID, completion: ScheduleEditorSession.Completion) {
        guard let editorSession, editorSession.id == requestID,
            editorSession.finish(using: router, completion: completion)
        else { return }
        self.editorSession = nil
        Task {
            _ = try? await scheduleModel.loadVisibleDays(
                centeredOn: completion.date,
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

private struct ScheduleEditorLoadKey: Equatable {
    let requestID: UUID
    let date: Date
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
    .environment(ScheduleEditorStore())
}
