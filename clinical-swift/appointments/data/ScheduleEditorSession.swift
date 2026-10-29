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
        let model = AppointmentBookingModel(
            selectedDate: selectedDate)
        // Clamp the centered interval at clinic boundaries, then keep the manual time on reload.
        let minutes = center.totalMinutes - model.draft.durationMinutes / 2
        // Only the initial start uses 15-minute steps. Later drags use five-minute steps.
        let snapped = max(Int((Double(minutes) / 15).rounded()) * 15, 0)
        @Dependency(\.calendar) var calendar
        model.draft.selectStart(
            TimeOfDay(snapped / 60, snapped % 60).on(date: selectedDate, using: calendar))
        editor = .appointment(model)
        adjustment.begin(preview, edge: .move, items: items)
    }

    init?(
        request: AppPresentation, selectedDate: Date, appointments: [Appointment],
        onFinished: @escaping (Date) -> Void
    ) {
        id = request.id
        self.onFinished = onFinished
        switch request {
        case .scheduleCreation, .appointmentBooking:
            let patient: Patient?
            if case .appointmentBooking(let request) = request {
                patient = request.patient
                allowsTypeSelection = false
            } else {
                patient = nil
                allowsTypeSelection = true
                isShowingSheet = true
            }
            let model = AppointmentBookingModel(
                selectedDate: selectedDate, selectedPatient: patient)
            @Dependency(\.calendar) var calendar
            @Dependency(\.date.now) var now
            let earliestStart: Date?
            if calendar.isDate(selectedDate, inSameDayAs: now) {
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
        case .appointmentEdit(let request):
            allowsTypeSelection = false
            // Use the details that were already visible so the editor can start without another read.
            // Saving still validates the current stored appointment before writing.
            let model = AppointmentBookingModel(
                editing: request.details)
            editor = .appointment(model)
        case .unavailableTimeEditor(let request):
            allowsTypeSelection = false
            editor = .unavailableTime(
                UnavailableTimeEditorModel(
                    editing: request.block))
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
        @Dependency(\.calendar) var calendar
        return calendar.startOfDay(for: preview.start)
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
        @Dependency(\.calendar) var calendar
        guard allowsDateSelection, !adjustment.isDragging,
            !calendar.isDate(date, inSameDayAs: selectedDate)
        else { return }
        let start = TimeOfDay(date: preview.start, calendar: calendar).on(
            date: date, using: calendar)
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
            case .appointment(let model): try await model.save()
            case .unavailableTime(let model): try await model.save()
            }
        }
    }

    @discardableResult
    func delete() async -> Bool {
        guard canDelete, !isWorking, !didFinish,
            case .unavailableTime(let model) = editor
        else { return false }
        return await perform(deleting: true) { try await model.delete() }
    }

    private func perform(
        deleting: Bool = false, operation: () async throws -> Date
    ) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        adjustment.release()
        errorMessage = nil
        do {
            let date = try await operation()
            didFinish = true
            onFinished(date)
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
