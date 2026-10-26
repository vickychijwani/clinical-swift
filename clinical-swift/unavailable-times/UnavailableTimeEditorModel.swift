import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

struct UnavailableTimeDraft: Equatable {
    var label: String
    var start: Date
    var durationMinutes: Int

    func validate() throws {
        @Dependency(\.calendar) var calendar
        let opening = Bitehaus.opening.on(date: start, using: calendar)
        let closing = Bitehaus.closing.on(date: start, using: calendar)
        guard durationMinutes > 0,
            start >= opening,
            let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start),
            end <= closing
        else { throw UnavailableTimeError.invalidTime }
    }

    mutating func move(to date: Date) {
        @Dependency(\.calendar) var calendar
        let clock = TimeOfDay(date: start, calendar: calendar)
        let latest = Bitehaus.closing.totalMinutes - durationMinutes
        let minutes = max(Bitehaus.opening.totalMinutes, min(clock.totalMinutes, latest))
        start = TimeOfDay(minutes / 60, minutes % 60).on(date: date, using: calendar)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label.nilIfBlank == rhs.label.nilIfBlank
            && lhs.start == rhs.start && lhs.durationMinutes == rhs.durationMinutes
    }
}

@MainActor @Observable
final class UnavailableTimeEditorModel: Identifiable {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.date.now) private var now

    let id: UUID
    let purpose: UnavailableTimeEditorPurpose
    let blockID: UUID
    let adjustment = TimelineAdjustment()
    let originalDraft: UnavailableTimeDraft
    var draft: UnavailableTimeDraft
    var isEditingLabel = false
    private(set) var isSaving = false
    private(set) var isDeleting = false
    private(set) var didFinish = false
    private(set) var draftPreviewScrollRequest = 0
    var errorMessage: String?
    var onFinished: (Date) -> Void

    init(id: UUID = UUID(), selectedDate: Date, onFinished: @escaping (Date) -> Void) {
        @Dependency(\.calendar) var calendar
        self.id = id
        purpose = .create
        isEditingLabel = true
        blockID = UUID()
        let initialDraft = UnavailableTimeDraft(
            label: "",
            start: Bitehaus.opening.on(date: selectedDate, using: calendar),
            durationMinutes: 60
        )
        draft = initialDraft
        originalDraft = initialDraft
        self.onFinished = onFinished
    }

    init(id: UUID = UUID(), editing block: UnavailableTime, onFinished: @escaping (Date) -> Void) {
        self.id = id
        purpose = .edit(block)
        blockID = block.id
        // Keep stored values unchanged until the user changes a schedule control.
        let initialDraft = UnavailableTimeDraft(
            label: block.label ?? "", start: block.start, durationMinutes: block.durationMinutes
        )
        draft = initialDraft
        originalDraft = initialDraft
        self.onFinished = onFinished
    }

    var isWorking: Bool { isSaving || isDeleting }
    var hasUnsavedChanges: Bool {
        UnavailableTimeDraft(
            label: draft.label, start: preview.start, durationMinutes: preview.durationMinutes)
            != originalDraft
    }
    var selectedDate: Date { calendar.startOfDay(for: preview.start) }
    var preview: UnavailableTime {
        UnavailableTime(
            id: blockID, label: draft.label, start: adjustment.preview?.start ?? draft.start,
            durationMinutes: adjustment.preview?.durationMinutes ?? draft.durationMinutes
        )
    }

    func startTimelineEditing() {
        adjustment.select(.unavailableTime(preview))
    }

    func finishLabelEntry() {
        guard !isWorking else { return }
        applyTimelinePreview()
        adjustment.select(.unavailableTime(draftBlock))
        isEditingLabel = false
    }

    func selectDate(_ date: Date) {
        guard !calendar.isDate(date, inSameDayAs: preview.start), !isWorking else { return }
        if adjustment.isActive {
            _ = adjustment.selectDate(date)
            applyTimelinePreview()
        } else {
            draft.move(to: date)
        }
        draftPreviewScrollRequest += 1
    }

    func selectStart(_ start: Date) {
        guard !isWorking else { return }
        applyTimelinePreview()
        let date = selectedDate
        draft.start = start
        draft.move(to: date)
        if adjustment.isActive { adjustment.select(.unavailableTime(draftBlock)) }
        draftPreviewScrollRequest += 1
    }

    func selectDuration(_ minutes: Int) {
        guard !isWorking else { return }
        applyTimelinePreview()
        draft.durationMinutes = minutes
        draft.move(to: selectedDate)
        if adjustment.isActive { adjustment.select(.unavailableTime(draftBlock)) }
        draftPreviewScrollRequest += 1
    }

    @discardableResult
    func save() async -> Bool {
        guard !isWorking, !didFinish, !adjustment.isDragging else { return false }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        applyTimelinePreview()
        do {
            try draft.validate()
            let record = UnavailableTimeRecord(
                id: blockID, label: draft.label.nilIfBlank, start: draft.start,
                durationMinutes: draft.durationMinutes, createdAt: now, updatedAt: now
            )
            let isEditing = purpose.editedID != nil
            try await database.write { db in
                if isEditing {
                    guard try UnavailableTimeRecord.find(record.id).fetchOne(db) != nil else {
                        throw UnavailableTimeError.missingRecord
                    }
                    try UnavailableTimeRecord.find(record.id).update {
                        $0.label = record.label
                        $0.start = record.start
                        $0.durationMinutes = record.durationMinutes
                        $0.updatedAt = record.updatedAt
                    }.execute(db)
                } else {
                    try UnavailableTimeRecord.insert { record }.execute(db)
                }
            }
            didFinish = true
            onFinished(record.start)
            return true
        } catch {
            errorMessage =
                (error as? UnavailableTimeError)?.message
                ?? "The unavailable time could not be saved."
            return false
        }
    }

    @discardableResult
    func delete() async -> Bool {
        guard !isWorking, !didFinish, !adjustment.isDragging,
            let targetID = purpose.editedID
        else { return false }
        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil
        let date = selectedDate
        do {
            try await database.write { db in
                guard try UnavailableTimeRecord.find(targetID).fetchOne(db) != nil else {
                    throw UnavailableTimeError.missingRecord
                }
                try UnavailableTimeRecord.find(targetID).delete().execute(db)
            }
            didFinish = true
            onFinished(date)
            return true
        } catch {
            errorMessage =
                (error as? UnavailableTimeError)?.message
                ?? "The unavailable time could not be deleted."
            return false
        }
    }

    private var draftBlock: UnavailableTime {
        UnavailableTime(
            id: blockID, label: draft.label, start: draft.start,
            durationMinutes: draft.durationMinutes)
    }

    private func applyTimelinePreview() {
        guard let preview = adjustment.preview else { return }
        draft.start = preview.start
        draft.durationMinutes = preview.durationMinutes
    }
}

nonisolated enum UnavailableTimeEditorPurpose: Sendable {
    case create
    case edit(UnavailableTime)

    var editedID: UUID? {
        guard case .edit(let block) = self else { return nil }
        return block.id
    }

    var title: String { editedID == nil ? "Unavailable Time" : "Edit Unavailable Time" }
}

nonisolated enum UnavailableTimeError: Error {
    case invalidTime
    case missingRecord

    var message: String {
        switch self {
        case .invalidTime: "Choose a positive duration within clinic hours."
        case .missingRecord: "This unavailable time no longer exists."
        }
    }
}
