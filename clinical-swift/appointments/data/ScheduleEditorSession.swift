import ClinicalModels
import Dependencies
import Foundation

@MainActor
struct ScheduleEditorSession: Identifiable {
    let id: UUID
    let editor: Editor

    enum Editor {
        case appointment(AppointmentBookingModel)
        case unavailableTime(UnavailableTimeEditorModel)
    }

    init(
        bookingID: UUID, selectedDate: Date, center: TimeOfDay, items: [TimelineItem],
        onFinished: @escaping (Date) -> Void
    ) {
        id = bookingID
        let model = AppointmentBookingModel(selectedDate: selectedDate, onSaved: onFinished)
        model.beginTimelineBooking(center: center, items: items)
        editor = .appointment(model)
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
            model.startTimelineEditing()
            editor = .appointment(model)
        case .appointmentEdit(let request):
            // Use the details that were already visible so the editor can start without another read.
            // Saving still validates the current stored appointment before writing.
            let model = AppointmentBookingModel(editing: request.details, onSaved: onFinished)
            model.updateAppointments(appointments, for: selectedDate)
            model.startTimelineEditing()
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

    var adjustment: TimelineAdjustment {
        switch editor {
        case .appointment(let model): model.adjustment
        case .unavailableTime(let model): model.adjustment
        }
    }

    var isShowingSheet: Bool {
        get {
            switch editor {
            case .appointment(let model): model.isSelectingPatient
            case .unavailableTime(let model): model.isEditingLabel
            }
        }
        nonmutating set {
            switch editor {
            case .appointment(let model): model.isSelectingPatient = newValue
            case .unavailableTime(let model): model.isEditingLabel = newValue
            }
        }
    }

    var isWorking: Bool {
        switch editor {
        case .appointment(let model): model.isSaving
        case .unavailableTime(let model): model.isWorking
        }
    }

    var allowsDateSelection: Bool { !isWorking }

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
        get {
            switch editor {
            case .appointment(let model): model.saveErrorMessage
            case .unavailableTime(let model): model.errorMessage
            }
        }
        nonmutating set {
            switch editor {
            case .appointment(let model): model.saveErrorMessage = newValue
            case .unavailableTime(let model): model.errorMessage = newValue
            }
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

    func beginAdjustment(_ item: TimelineItem, edge: TimelineAdjustment.Edge, items: [TimelineItem])
    {
        guard !isWorking, item.id == preview.id else { return }
        adjustment.begin(preview, edge: edge, items: items)
    }

    @discardableResult
    func updateAdjustment(translation: CGFloat, items: [TimelineItem]) -> CGFloat {
        guard !isWorking else { return 0 }
        var draft = preview
        let correction = adjustment.update(&draft, translation: translation, items: items)
        // Keep gesture changes in the editor draft. Only Done writes them to storage.
        switch editor {
        case .appointment(let model):
            model.draft.start = draft.start
            model.draft.durationMinutes = draft.durationMinutes
        case .unavailableTime(let model):
            model.draft.start = draft.start
            model.draft.durationMinutes = draft.durationMinutes
        }
        return correction
    }

    func expandBreak(items: [TimelineItem]) -> CGFloat {
        adjustment.expandBreak(draft: preview, items: items)
    }

    func scale(_ items: [TimelineItem], on date: Date) -> TimelineScale {
        adjustment.scale(items, draft: preview, on: date)
    }

    func selectDate(_ date: Date) {
        guard allowsDateSelection, !adjustment.isDragging else { return }
        switch editor {
        case .appointment(let model): model.selectDate(date)
        case .unavailableTime(let model): model.selectDate(date)
        }
    }

    func releaseBooking(_ released: TimelineAdjustment) {
        guard case .appointment(let model) = editor, model.adjustment === released else { return }
        model.releaseTimelineBooking()
    }

    /// Done is the only action that writes these changes to storage.
    func save() async {
        guard !isWorking else { return }
        adjustment.release()
        switch editor {
        case .appointment(let model):
            if model.draft.selectedPatient == nil {
                model.releaseTimelineBooking()
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
