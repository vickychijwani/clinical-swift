import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

struct UnavailableTimeDraft {
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

}

@MainActor @Observable
final class UnavailableTimeEditorModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.date.now) private var now

    let purpose: UnavailableTimeEditorPurpose
    let blockID: UUID
    var draft: UnavailableTimeDraft

    init(
        start: Date, durationMinutes: Int
    ) {
        purpose = .create
        blockID = UUID()
        draft = UnavailableTimeDraft(
            label: "", start: start, durationMinutes: durationMinutes)
    }

    init(
        editing block: UnavailableTime
    ) {
        purpose = .edit(block)
        blockID = block.id
        // Keep stored values unchanged until the user changes a schedule control.
        draft = UnavailableTimeDraft(
            label: block.label ?? "", start: block.start, durationMinutes: block.durationMinutes
        )
    }

    var selectedDate: Date { calendar.startOfDay(for: draft.start) }
    var preview: UnavailableTime {
        UnavailableTime(
            id: blockID, label: draft.label, start: draft.start,
            durationMinutes: draft.durationMinutes
        )
    }

    func save() async throws -> Date {
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
        return record.start
    }

    func delete() async throws -> Date {
        guard let targetID = purpose.editedID else { throw UnavailableTimeError.missingRecord }
        let date = selectedDate
        try await database.write { db in
            guard try UnavailableTimeRecord.find(targetID).fetchOne(db) != nil else {
                throw UnavailableTimeError.missingRecord
            }
            try UnavailableTimeRecord.find(targetID).delete().execute(db)
        }
        return date
    }

}

nonisolated enum UnavailableTimeEditorPurpose: Sendable {
    case create
    case edit(UnavailableTime)

    var editedID: UUID? {
        guard case .edit(let block) = self else { return nil }
        return block.id
    }

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
