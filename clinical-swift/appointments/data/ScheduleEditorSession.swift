import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import Observation

/// Shared state survives a type change. Only the active domain model owns a draft.
@MainActor @Observable
final class ScheduleEditorSession: Identifiable {
    let id: UUID
    let allowsTypeSelection: Bool
    private(set) var editor: Editor
    let adjustment = TimelineAdjustment()
    var isShowingSheet = false
    private(set) var isWorking = false
    private(set) var didFinish = false
    var errorMessage: String?
    /// A counter keeps repeated scroll requests distinct; it has no domain meaning.
    private var scrollRevision = 0
    private let onFinished: (Completion) -> Void

    static let savedAppointmentToastDuration: Duration = .seconds(5)

    enum Completion: Equatable, Sendable {
        case appointmentSaved(AppointmentBookingModel.SavedAppointment)
        case unavailableTimeChanged(date: Date)
        case discarded(date: Date)

        var date: Date {
            switch self {
            case .appointmentSaved(let saved):
                saved.start
            case .unavailableTimeChanged(let date),
                .discarded(let date):
                date
            }
        }
    }

    enum Editor {
        case appointment(AppointmentBookingModel)
        case unavailableTime(UnavailableTimeEditorModel)
    }

    enum ItemType: String, CaseIterable {
        case appointment = "Appointment"
        case unavailableTime = "Unavailable Time"
    }

    init(
        bookingID: UUID, selectedDate: Date, center: TimeOfDay, items: [TimelineItem],
        onFinished: @escaping (Completion) -> Void
    ) {
        id = bookingID
        allowsTypeSelection = true
        self.onFinished = onFinished
        let model = AppointmentBookingModel(
            selectedDate: selectedDate)
        // Clamp the centered interval at clinic boundaries, then keep the manual time on reload.
        let minutes = center.totalMinutes - model.draft.durationMinutes / 2
        // Only the initial start uses 15-minute steps. Later drags use five-minute steps.
        let snapped = max(Int((Double(minutes) / 15).rounded()) * 15, 0)
        model.draft.selectStart(
            TimeOfDay(snapped / 60, snapped % 60).on(
                date: selectedDate, using: ClinicDate.calendar))
        editor = .appointment(model)
        adjustment.begin(preview, edge: .move, items: items)
    }

    init(
        request: ScheduleEditorRequest, selectedDate: Date, appointments: [Appointment],
        onFinished: @escaping (Completion) -> Void
    ) {
        id = request.id
        self.onFinished = onFinished
        switch request.kind {
        case .create, .bookAppointment:
            let patient: Patient?
            if case .bookAppointment(let requestedPatient) = request.kind {
                patient = requestedPatient
                allowsTypeSelection = false
            } else {
                patient = nil
                allowsTypeSelection = true
                isShowingSheet = true
            }
            let model = AppointmentBookingModel(
                selectedDate: selectedDate, selectedPatient: patient)
            let calendar = ClinicDate.calendar
            @Dependency(\.date.now) var now
            let earliestStart: Date?
            if selectedDate.isSameDayAs(now) {
                let minutes = TimeOfDay(date: now, calendar: calendar).totalMinutes
                earliestStart = now.startOfDay(using: calendar).addMinutes(
                    ((minutes + 4) / 5) * 5, using: calendar)
            } else {
                earliestStart = nil
            }
            let availability = AppointmentAvailability(
                searchDate: selectedDate, appointments: appointments, calendar: calendar)
            // Suggest once. Later date and schedule changes must keep manual choices, even
            // when they overlap another appointment or cross a clinic break.
            if let start = availability.firstAvailableSlot(
                neededDurationMinutes: model.draft.durationMinutes, earliestStart: earliestStart)
            {
                model.draft.start = start
            }
            // Install the model after prefilling slot - to ensure the sheet starts out displaying the
            // pre-selected slot rather than briefly showing the clinic opening time.
            editor = .appointment(model)
        case .editAppointment(let details):
            allowsTypeSelection = false
            // Use the details that were already visible so the editor can start without another read.
            // Saving still validates the current stored appointment before writing.
            let model = AppointmentBookingModel(
                editing: details)
            editor = .appointment(model)
        case .editUnavailableTime(let block):
            allowsTypeSelection = false
            editor = .unavailableTime(
                UnavailableTimeEditorModel(
                    editing: block))
        }
    }

    var itemType: ItemType {
        switch editor {
        case .appointment: .appointment
        case .unavailableTime: .unavailableTime
        }
    }

    func selectType(_ type: ItemType) {
        guard allowsTypeSelection, type != itemType, !isWorking, !didFinish else { return }
        adjustment.release()
        let interval = preview
        errorMessage = nil
        switch editor {
        case .appointment(let model):
            model.draft.selectedPatient = nil
            model.searchText = ""
        case .unavailableTime(let model):
            model.draft.label = ""
        }
        switch type {
        case .appointment:
            let model = AppointmentBookingModel(
                selectedDate: interval.start)
            model.draft.start = interval.start
            model.draft.durationMinutes = interval.durationMinutes
            editor = .appointment(model)
        case .unavailableTime:
            editor = .unavailableTime(
                UnavailableTimeEditorModel(
                    start: interval.start, durationMinutes: interval.durationMinutes))
        }
        // Replace the old model so its fields cannot return on a round trip.
        scrollRevision += 1
    }

    var selectedDate: Date {
        ClinicDate.day(preview.start)
    }

    var allowsDateSelection: Bool { !isWorking && !didFinish }

    var canDelete: Bool {
        guard case .unavailableTime(let model) = editor else { return false }
        return model.purpose.editedID != nil
    }

    var errorTitle: String {
        switch editor {
        case .appointment: "Unable to save appointment"
        case .unavailableTime: "Unable to change unavailable time"
        }
    }

    var preview: TimelineItem {
        switch editor {
        case .appointment(let model): .appointment(model.draftAppointment)
        case .unavailableTime(let model): .unavailableTime(model.preview)
        }
    }

    var scrollRequest: ScheduleEditorScrollRequest {
        ScheduleEditorScrollRequest(
            sessionID: id, date: selectedDate, revision: scrollRevision)
    }

    func selectPatient(_ patient: Patient) {
        guard !isWorking, !didFinish, case .appointment(let model) = editor else { return }
        model.draft.selectedPatient = patient
        model.searchText = ""
        isShowingSheet = false
    }

    func beginAdjustment(_ item: TimelineItem, edge: TimelineAdjustment.Edge, items: [TimelineItem])
    {
        guard allowsDateSelection, item.id == preview.id else { return }
        adjustment.begin(preview, edge: edge, items: items)
    }

    @discardableResult
    func updateAdjustment(translation: CGFloat, items: [TimelineItem]) -> CGFloat {
        guard allowsDateSelection else { return 0 }
        var draft = preview
        let correction = adjustment.update(&draft, translation: translation, items: items)
        // Keep gesture changes in the editor draft. Only Done writes them to storage.
        setInterval(start: draft.start, duration: draft.durationMinutes)
        return correction
    }

    private func setInterval(start: Date, duration: Int) {
        switch editor {
        case .appointment(let model):
            model.draft.start = start
            model.draft.durationMinutes = duration
            model.draft.selectedDate = selectedDate
        case .unavailableTime(let model):
            model.draft.start = start
            model.draft.durationMinutes = duration
        }
    }

    func expandBreak(items: [TimelineItem]) -> CGFloat {
        adjustment.expandBreak(draft: preview, items: items)
    }

    func scale(_ items: [TimelineItem], on date: Date) -> TimelineScale {
        adjustment.scale(items, draft: preview, on: date)
    }

    func selectDate(_ date: Date) {
        guard allowsDateSelection, !adjustment.isDragging,
            !date.isSameDayAs(selectedDate)
        else { return }
        let start = TimeOfDay(date: preview.start, calendar: ClinicDate.calendar).on(
            date: date, using: ClinicDate.calendar)
        setInterval(start: start, duration: preview.durationMinutes)
        scrollRevision += 1
    }

    func releaseBooking(_ released: TimelineAdjustment) {
        guard adjustment === released else { return }
        adjustment.release()
        isShowingSheet = true
    }

    /// Done is the only action that writes these changes to storage.
    @discardableResult
    func save() async -> Bool {
        guard !isWorking, !didFinish else { return false }
        if case .appointment(let model) = editor, model.draft.selectedPatient == nil {
            adjustment.release()
            isShowingSheet = true
            return false
        }
        return await perform {
            switch editor {
            case .appointment(let model):
                return .appointmentSaved(try await model.save())
            case .unavailableTime(let model):
                return .unavailableTimeChanged(date: try await model.save())
            }
        }
    }

    @discardableResult
    func delete() async -> Bool {
        guard canDelete, !isWorking, !didFinish,
            case .unavailableTime(let model) = editor
        else { return false }
        return await perform(deleting: true) {
            .unavailableTimeChanged(date: try await model.delete())
        }
    }

    private func perform(
        deleting: Bool = false, operation: () async throws -> Completion
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        adjustment.release()
        errorMessage = nil
        do {
            let completion = try await operation()
            didFinish = true
            onFinished(completion)
            return true
        } catch {
            switch editor {
            case .appointment:
                errorMessage =
                    switch error {
                    case AppointmentBookingValidationError.missingPatient: "Select a patient."
                    case AppointmentBookingValidationError.invalidTime:
                        "Choose a time within clinic hours."
                    case AccountEntryError.appointmentHasCharges:
                        "This appointment has charges. Remove its linked charges before changing the patient."
                    case is AppointmentEditingError: "This appointment can no longer be edited."
                    default: "The appointment could not be saved."
                    }
            case .unavailableTime:
                errorMessage =
                    (error as? UnavailableTimeError)?.message
                    ?? (deleting
                        ? "The unavailable time could not be deleted."
                        : "The unavailable time could not be saved.")
            }
            return false
        }
    }

    func visibleItems(_ items: [TimelineItem], for date: Date) -> [TimelineItem] {
        let editedID: TimelineItem.ID?
        switch editor {
        case .appointment(let model):
            // Hide the stored version on every page while its draft moves between dates.
            editedID = model.purpose.editedAppointmentID.map { .appointment($0) }
        case .unavailableTime(let model):
            editedID = model.purpose.editedID.map { .unavailableTime($0) }
        }
        var items = items.filter { $0.id != editedID }
        let preview = preview
        if preview.start.isSameDayAs(date) {
            items.append(preview)
        }
        return items
    }

    @discardableResult
    func finish(
        using router: Router,
        completion: Completion
    ) -> Bool {
        // A late save must not close a newer presentation or change its date.
        guard router.activePresentation?.id == id else { return false }
        router.finishScheduleEditor(id, date: completion.date)
        showToastIfNeeded(for: completion, using: router)
        return true
    }

    private func showToastIfNeeded(
        for completion: Completion,
        using router: Router
    ) {
        guard case .appointmentSaved(let saved) = completion else { return }
        let message =
            switch saved.kind {
            case .booked: "Appointment booked"
            case .rescheduled: "Appointment rescheduled"
            case .updated: "Appointment updated"
            }
        let action: ToastAction? =
            switch saved.kind {
            case .booked, .rescheduled:
                ToastAction(
                    title: "Message",
                    systemImage: "arrow.up.message"
                ) { [weak router] in
                    router?.requestAppointmentMessage(id: saved.id, date: saved.start)
                }
            case .updated:
                nil
            }
        router.toast.show(
            ToastItem(
                message: message,
                action: action,
                duration: Self.savedAppointmentToastDuration
            )
        )
    }
}

nonisolated struct ScheduleEditorScrollRequest: Equatable {
    let sessionID: UUID
    let date: Date
    let revision: Int
}

/// The timeline owns this session. The app root reads it to present fields on the shared surface.
@MainActor @Observable
final class ScheduleEditorStore {
    private(set) var session: ScheduleEditorSession?

    init(session: ScheduleEditorSession? = nil) {
        self.session = session
    }

    func hasEditor(for router: Router) -> Bool {
        router.scheduleEditorRequest != nil || session != nil
    }

    func activeSession(for request: ScheduleEditorRequest) -> ScheduleEditorSession? {
        guard let session, session.id == request.id else { return nil }
        return session
    }

    func selectedDate(using router: Router) -> Date {
        session?.selectedDate ?? router.selectedScheduleDate
    }

    func selectDate(_ date: Date, using router: Router) {
        guard session?.allowsDateSelection != false,
            session?.adjustment.isDragging != true
        else { return }
        let selectedDate = ClinicDate.day(date)
        router.selectScheduleDate(selectedDate)
        session?.selectDate(selectedDate)
    }

    func clearIfMismatching(_ requestID: UUID?) {
        if session?.id != requestID {
            session = nil
        }
    }

    func beginHold(
        on item: TimelineItem?,
        center: TimeOfDay,
        date: Date,
        items: [TimelineItem],
        router: Router,
        detailsForAppointment: (Appointment) -> AppointmentDetails?,
        onFinished: @escaping (UUID, ScheduleEditorSession.Completion) -> Void
    ) -> ScheduleEditorSession? {
        guard !hasEditor(for: router),
            date.isSameDayAs(router.selectedScheduleDate)
        else { return nil }
        if let item {
            guard item.allowsAdjustment else { return nil }
            switch item {
            case .appointment(let appointment):
                guard let details = detailsForAppointment(appointment),
                    details.appointment.status == .scheduled
                else { return nil }
                router.requestAppointmentEdit(details)
            case .unavailableTime(let block):
                router.requestUnavailableTimeEdit(block)
            }
            guard let request = router.scheduleEditorRequest else { return nil }
            let session = ScheduleEditorSession(
                request: request,
                selectedDate: date,
                appointments: []
            ) { completion in
                onFinished(request.id, completion)
            }
            session.beginAdjustment(item, edge: .move, items: items)
            self.session = session
            return session
        }
        router.requestScheduleCreation()
        guard let request = router.scheduleEditorRequest, case .create = request.kind else {
            return nil
        }
        let session = ScheduleEditorSession(
            bookingID: request.id,
            selectedDate: date,
            center: center,
            items: items
        ) { completion in
            onFinished(request.id, completion)
        }
        self.session = session
        return session
    }

    /// Creates a session for the active request and discards stale async reads if the request
    /// or selected schedule date changes before initialization finishes.
    func prepare(
        request: ScheduleEditorRequest?,
        router: Router,
        appointmentsForBooking: (Date) async -> [Appointment],
        onFinished: @escaping (UUID, ScheduleEditorSession.Completion) -> Void
    ) async {
        guard let request else {
            session = nil
            return
        }
        // A timeline hold installs its session before the first drag update.
        guard session?.id != request.id else { return }
        session = nil
        let selectedDate = router.selectedScheduleDate
        let appointments: [Appointment]
        if request.needsBookingAvailability {
            appointments = await appointmentsForBooking(selectedDate)
            guard !Task.isCancelled,
                router.scheduleEditorRequest?.id == request.id,
                selectedDate.isSameDayAs(router.selectedScheduleDate)
            else { return }
        } else {
            appointments = []
        }
        guard session?.id != request.id else { return }
        session = ScheduleEditorSession(
            request: request,
            selectedDate: selectedDate,
            appointments: appointments
        ) { completion in
            onFinished(request.id, completion)
        }
    }

    @discardableResult
    func finish(
        _ requestID: UUID,
        completion: ScheduleEditorSession.Completion,
        router: Router
    ) -> Bool {
        guard let session, session.id == requestID,
            session.finish(using: router, completion: completion)
        else { return false }
        self.session = nil
        return true
    }
}
