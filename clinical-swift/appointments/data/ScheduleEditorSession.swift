import ClinicalModels
import Dependencies
import Foundation
import Observation

/// Shared state survives a type change. Only the active domain model owns a draft.
@MainActor @Observable
final class ScheduleEditorState {
    let adjustment = TimelineAdjustment()
    var isShowingSheet = false
    var isWorking = false
    var didFinish = false
    var errorMessage: String?
    var scrollRevision = 0
}

@MainActor @Observable
final class ScheduleEditorSession: Identifiable {
    let id: UUID
    let allowsTypeSelection: Bool
    private(set) var editor: Editor
    let state: ScheduleEditorState
    private let onFinished: (Date) -> Void

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
        onFinished: @escaping (Date) -> Void
    ) {
        id = bookingID
        allowsTypeSelection = true
        self.onFinished = onFinished
        state = ScheduleEditorState()
        let model = AppointmentBookingModel(
            selectedDate: selectedDate, state: state, onSaved: onFinished)
        // Clamp the centered interval at clinic boundaries, then keep the manual time on reload.
        let minutes = center.totalMinutes - model.draft.durationMinutes / 2
        // Only the initial start uses 15-minute steps. Later drags use five-minute steps.
        let snapped = max(Int((Double(minutes) / 15).rounded()) * 15, 0)
        @Dependency(\.calendar) var calendar
        model.draft.selectStart(
            TimeOfDay(snapped / 60, snapped % 60).on(date: selectedDate, using: calendar))
        model.startTimelineEditing()
        editor = .appointment(model)
        adjustment.begin(preview, edge: .move, items: items)
    }

    init?(
        request: AppPresentation, selectedDate: Date, appointments: [Appointment],
        onFinished: @escaping (Date) -> Void
    ) {
        id = request.id
        self.onFinished = onFinished
        state = ScheduleEditorState()
        switch request {
        case .scheduleCreation, .appointmentBooking:
            let patient: Patient?
            if case .appointmentBooking(let request) = request {
                patient = request.patient
                allowsTypeSelection = false
            } else {
                patient = nil
                allowsTypeSelection = true
                state.isShowingSheet = true
            }
            let model = AppointmentBookingModel(
                selectedDate: selectedDate, selectedPatient: patient, state: state,
                onSaved: onFinished)
            model.updateAppointments(appointments, for: selectedDate)
            model.prefillFirstAvailableSlot()
            // Install the model after prefilling slot - to ensure the sheet starts out displaying the
            // pre-selected slot rather than briefly showing the clinic opening time.
            model.startTimelineEditing()
            editor = .appointment(model)
        case .appointmentEdit(let request):
            allowsTypeSelection = false
            // Use the details that were already visible so the editor can start without another read.
            // Saving still validates the current stored appointment before writing.
            let model = AppointmentBookingModel(
                editing: request.details, state: state, onSaved: onFinished)
            model.updateAppointments(appointments, for: selectedDate)
            model.startTimelineEditing()
            editor = .appointment(model)
        case .unavailableTimeEditor(let request):
            allowsTypeSelection = false
            editor = .unavailableTime(
                UnavailableTimeEditorModel(
                    editing: request.block, state: state, onFinished: onFinished))
        default:
            return nil
        }
    }

    var itemType: ItemType {
        switch editor {
        case .appointment: .appointment
        case .unavailableTime: .unavailableTime
        }
    }

    func selectType(_ type: ItemType) {
        guard allowsTypeSelection, type != itemType, !isWorking, !state.didFinish else { return }
        adjustment.release()
        let interval = preview
        state.errorMessage = nil
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
                selectedDate: interval.start, state: state, onSaved: onFinished)
            model.draft.start = interval.start
            model.draft.durationMinutes = interval.durationMinutes
            model.startTimelineEditing()
            editor = .appointment(model)
        case .unavailableTime:
            editor = .unavailableTime(
                UnavailableTimeEditorModel(
                    start: interval.start, durationMinutes: interval.durationMinutes,
                    state: state, onFinished: onFinished))
        }
        // Replace the old model so its fields cannot return on a round trip.
        state.scrollRevision += 1
    }

    var selectedDate: Date {
        @Dependency(\.calendar) var calendar
        return calendar.startOfDay(for: preview.start)
    }

    var adjustment: TimelineAdjustment { state.adjustment }
    var isShowingSheet: Bool {
        get { state.isShowingSheet }
        set { state.isShowingSheet = newValue }
    }
    var isWorking: Bool { state.isWorking }
    var allowsDateSelection: Bool { !isWorking && !state.didFinish }

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

    var errorMessage: String? {
        get { state.errorMessage }
        set { state.errorMessage = newValue }
    }

    var preview: TimelineItem {
        switch editor {
        case .appointment(let model): .appointment(model.draftAppointment)
        case .unavailableTime(let model): .unavailableTime(model.preview)
        }
    }

    var scrollRequest: ScheduleEditorScrollRequest {
        ScheduleEditorScrollRequest(
            sessionID: id, date: selectedDate, revision: state.scrollRevision)
    }

    func selectPatient(_ patient: Patient) {
        guard !isWorking, case .appointment(let model) = editor else { return }
        model.selectPatient(patient)
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
        @Dependency(\.calendar) var calendar
        guard allowsDateSelection, !adjustment.isDragging,
            !calendar.isDate(date, inSameDayAs: selectedDate)
        else { return }
        let start = TimeOfDay(date: preview.start, calendar: calendar).on(
            date: date, using: calendar)
        setInterval(start: start, duration: preview.durationMinutes)
        state.scrollRevision += 1
    }

    func releaseBooking(_ released: TimelineAdjustment) {
        guard adjustment === released else { return }
        adjustment.release()
        isShowingSheet = true
    }

    /// Done is the only action that writes these changes to storage.
    func save() async {
        guard !isWorking, !state.didFinish else { return }
        adjustment.release()
        switch editor {
        case .appointment(let model):
            if model.draft.selectedPatient == nil {
                isShowingSheet = true
                return
            }
            _ = await model.saveAppointment()
        case .unavailableTime(let model):
            _ = await model.save()
        }
    }

    func delete() async {
        guard canDelete, !isWorking, case .unavailableTime(let model) = editor else { return }
        adjustment.release()
        _ = await model.delete()
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
            // Hide the stored version on every page while its draft moves between dates.
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
