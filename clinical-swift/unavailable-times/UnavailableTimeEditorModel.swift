import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

struct UnavailableTimeDraft {
    var label: String
    var start: Date
    var durationMinutes: Int

    func validate() throws {
        let opening = Bitehaus.opening.on(date: start, using: ClinicDate.calendar)
        let closing = Bitehaus.closing.on(date: start, using: ClinicDate.calendar)
        guard durationMinutes > 0,
            start >= opening,
            let end = ClinicDate.calendar.date(byAdding: .minute, value: durationMinutes, to: start),
            end <= closing
        else { throw UnavailableTimeError.invalidTime }
    }

}

@MainActor @Observable
final class UnavailableTimeEditorModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

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

    var selectedDate: Date { ClinicDate.day(draft.start) }
    var preview: UnavailableTime {
        UnavailableTime(
            id: blockID, label: draft.label, start: draft.start,
            durationMinutes: draft.durationMinutes
        )
    }

    func save() async throws -> Date {
        let isEditing = purpose.editedID != nil
        let action = isEditing ? "edit" : "create"
        do {
            try draft.validate()
            let record = UnavailableTimeRecord(
                id: blockID, label: draft.label.nilIfBlank, start: draft.start,
                durationMinutes: draft.durationMinutes, createdAt: now, updatedAt: now
            )
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
            telemetry.event(
                category: .unavailableTime,
                name: isEditing ? "unavailable_time_updated" : "unavailable_time_created",
                recordID: blockID.uuidString.lowercased(),
                action: action
            )
            return record.start
        } catch {
            telemetry.log(
                .error,
                category: .unavailableTime,
                name: "unavailable_time_save_failed",
                message: "Unavailable time save failed",
                error: error,
                recordID: blockID.uuidString.lowercased(),
                action: action
            )
            throw error
        }
    }

    func delete() async throws -> Date {
        guard let targetID = purpose.editedID else { throw UnavailableTimeError.missingRecord }
        let date = selectedDate
        do {
            try await database.write { db in
                guard try UnavailableTimeRecord.find(targetID).fetchOne(db) != nil else {
                    throw UnavailableTimeError.missingRecord
                }
                try UnavailableTimeRecord.find(targetID).delete().execute(db)
            }
            telemetry.event(
                category: .unavailableTime,
                name: "unavailable_time_deleted",
                recordID: targetID.uuidString.lowercased(),
                action: "delete"
            )
            return date
        } catch {
            telemetry.log(
                .error,
                category: .unavailableTime,
                name: "unavailable_time_delete_failed",
                message: "Unavailable time delete failed",
                error: error,
                recordID: targetID.uuidString.lowercased(),
                action: "delete"
            )
            throw error
        }
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

enum UnavailableTimeLookup {
    static func fetch(id: UUID) async throws -> UnavailableTime? {
        @Dependency(\.defaultDatabase) var database
        return try await database.read { db in
            try UnavailableTimeRecord.find(id).fetchOne(db)?.unavailableTime
        }
    }

    @MainActor
    static func resolve(_ request: UnavailableTimeNavigationRequest, using router: Router) async {
        do {
            let block = try await fetch(id: request.blockID)
            router.completeUnavailableTimeNavigation(request, block: block)
        } catch is CancellationError {
            return
        } catch {
            router.failUnavailableTimeNavigation(request, error: error)
        }
    }
}
