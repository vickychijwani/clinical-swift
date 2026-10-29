import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct UnavailableTimeTests {
    @Test func createEditDeleteKeepIdentityAndTimestamps() async throws {
        let database = try makeDatabase()
        let date = try instant("2026-10-02T09:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            var finishedDates: [Date] = []
            let (create, createModel) = try creatingSession(start: date, durationMinutes: 30) {
                finishedDates.append($0)
            }
            #expect(createModel.draft.start == date)
            #expect(createModel.draft.durationMinutes == 30)
            createModel.draft.label = " \n "
            #expect(await create.save())
            #expect(!(await create.save()))
            let createdID = createModel.blockID
            let record = try #require(
                try await database.read { db in
                    try UnavailableTimeRecord.find(createdID).fetchOne(db)
                })
            #expect(record.label == nil)
            #expect(record.unavailableTime.displayLabel == "Blocked")
            let editDate = date.addingTimeInterval(3600)
            let (edit, editModel) = try withDependencies {
                $0.date.now = editDate
            } operation: {
                try editingSession(record.unavailableTime) {
                    finishedDates.append($0)
                }
            }
            #expect(editModel.draft.start == record.start)
            editModel.draft.label = " Travel "
            editModel.draft.durationMinutes = 120
            #expect(
                await withDependencies {
                    $0.date.now = editDate
                } operation: {
                    await edit.save()
                })
            let updated = try #require(
                try await database.read { db in
                    try UnavailableTimeRecord.find(record.id).fetchOne(db)
                })
            #expect(updated.id == record.id)
            #expect(updated.createdAt == record.createdAt)
            #expect(updated.updatedAt == editDate)
            #expect(updated.label == "Travel")
            #expect(updated.durationMinutes == 120)
            let (delete, _) = try editingSession(updated.unavailableTime) {
                finishedDates.append($0)
            }
            #expect(await delete.delete())
            #expect(!(await delete.delete()))
            #expect(
                try await database.read { db in try UnavailableTimeRecord.count().fetchOne(db) }
                    == 0)
            #expect(finishedDates.count == 3)
        }
    }

    @Test func validationAllowsBreaksAndRejectsInvalidIntervals() async throws {
        let database = try makeDatabase()
        let date = try instant("2026-10-02T09:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let (session, model) = try creatingSession(start: date, durationMinutes: 30) { _ in }
            model.draft.start = try instant("2026-10-02T13:00:00Z")
            model.draft.durationMinutes = 120
            try model.draft.validate()
            #expect(await session.save())
            for (start, duration) in [
                ("2026-10-02T08:59:00Z", 30), ("2026-10-02T20:30:00Z", 60),
                ("2026-10-02T09:00:00Z", 0),
            ] {
                let invalid = UnavailableTimeDraft(
                    label: "", start: try instant(start), durationMinutes: duration)
                #expect(throws: UnavailableTimeError.self) { try invalid.validate() }
            }
        }
    }

    @Test func missingRowsAndWriteFailuresKeepEditorOpen() async throws {
        let database = try makeDatabase()
        let start = try instant("2026-10-02T14:07:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = start
        } operation: {
            let block = UnavailableTime(start: start, durationMinutes: 45)
            var didFinish = false
            let (session, model) = try editingSession(block) { _ in didFinish = true }
            #expect(model.draft.start == start)
            #expect(!(await session.save()))
            #expect(!(await session.delete()))
            #expect(session.errorMessage == "This unavailable time no longer exists.")
            #expect(!didFinish)
            let (create, _) = try creatingSession(start: start, durationMinutes: 30) { _ in
                didFinish = true
            }
            try await database.write { db in
                try db.execute(
                    sql:
                        "CREATE TRIGGER reject_blocks BEFORE INSERT ON unavailableTimes BEGIN SELECT RAISE(ABORT, 'test failure'); END"
                )
            }
            #expect(!(await create.save()))
            #expect(create.errorMessage != nil)
            #expect(!create.isWorking)
            #expect(!didFinish)
            #expect(
                try await database.read { db in
                    try UnavailableTimeCalendarSyncRecord.count().fetchOne(db)
                } == 0)
        }
    }

    @Test func reopeningKeepsBlocksAndConstraints() throws {
        let url = URL.temporaryDirectory.appending(path: "unavailable-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let start = try instant("2026-10-02T09:00:00Z")
        let id = UUID()
        do {
            let database = try DatabaseQueue(path: url.path)
            try migrateDatabase(database)
            try database.write { db in
                try UnavailableTimeRecord.insert {
                    UnavailableTimeRecord(
                        id: id, label: "Travel", start: start, durationMinutes: 60,
                        createdAt: start, updatedAt: start)
                }.execute(db)
            }
        }
        let reopened = try DatabaseQueue(path: url.path)
        try migrateDatabase(reopened)
        #expect(
            try reopened.read { db in try UnavailableTimeRecord.find(id).fetchOne(db)?.label }
                == "Travel")
        #expect(throws: DatabaseError.self) {
            try reopened.write { db in
                try db.execute(sql: "UPDATE unavailableTimes SET durationMinutes = 0")
            }
        }
    }

    @Test func triggersPreserveLinksAndIgnoreTimestampOnlyUpdates() throws {
        let database = try makeDatabase()
        let start = try instant("2026-10-02T09:00:00Z")
        let id = UUID()
        try database.write { db in
            try UnavailableTimeRecord.insert {
                UnavailableTimeRecord(
                    id: id, start: start, durationMinutes: 60, createdAt: start, updatedAt: start)
            }.execute(db)
            try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }.update {
                $0.eventIdentifier = #bind("event-1")
                $0.eventStart = #bind(start)
                $0.needsSync = false
            }.execute(db)
            try UnavailableTimeRecord.find(id).update {
                $0.label = #bind(nil, as: String?.self)
                $0.start = start
                $0.durationMinutes = 60
                $0.updatedAt = start.addingTimeInterval(60)
            }.execute(db)
        }
        var row = try #require(
            try database.read { db in
                try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }
                    .fetchOne(db)
            })
        #expect(row.revision == 1)
        #expect(!row.needsSync)
        try database.write { db in
            try UnavailableTimeRecord.find(id).update { $0.label = #bind("Travel") }.execute(db)
            try UnavailableTimeRecord.find(id).delete().execute(db)
        }
        row = try #require(
            try database.read { db in
                try UnavailableTimeCalendarSyncRecord.where { $0.unavailableTimeID.eq(id) }
                    .fetchOne(db)
            })
        #expect(row.revision == 3)
        #expect(row.needsSync)
        #expect(row.eventIdentifier == "event-1")
        #expect(row.eventStart == start)
        #expect(
            try database.read { db in try AppointmentCalendarSyncRecord.count().fetchOne(db) } == 0)
        #expect(try database.read { db in try AppointmentRecord.count().fetchOne(db) } == 0)
    }

    @Test func repeatedConcurrentSaveAndDeleteHaveOnlyOneResult() async throws {
        let database = try makeDatabase()
        let date = try instant("2026-10-02T09:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            var finished = 0
            let (create, createModel) = try creatingSession(start: date, durationMinutes: 30) { _ in
                finished += 1
            }
            let first = Task { await create.save() }
            let second = Task { await create.save() }
            let results = await [first.value, second.value]
            #expect(results.filter { $0 }.count == 1)
            #expect(finished == 1)
            let recordID = createModel.blockID
            let block = try #require(
                try await database.read { db in
                    try UnavailableTimeRecord.find(recordID).fetchOne(db)?.unavailableTime
                })
            let (edit, _) = try editingSession(block) { _ in finished += 1 }
            let save = Task { await edit.save() }
            let delete = Task { await edit.delete() }
            let editResults = await [save.value, delete.value]
            #expect(editResults.filter { $0 }.count == 1)
            #expect(finished == 2)
            #expect(!edit.isWorking)
        }
    }

    @Test func failedEditAndDeleteKeepTheRowAndItsDeliveryRevision() async throws {
        let database = try makeDatabase()
        let date = try instant("2026-10-02T09:00:00Z")
        try await withDependencies {
            $0.defaultDatabase = database
            $0.calendar = utcCalendar
            $0.date.now = date
        } operation: {
            let (create, createModel) = try creatingSession(start: date, durationMinutes: 30) { _ in
            }
            #expect(await create.save())
            let recordID = createModel.blockID
            let block = try #require(
                try await database.read { db in
                    try UnavailableTimeRecord.find(recordID).fetchOne(db)?.unavailableTime
                })
            try await database.write { db in
                try db.execute(
                    sql:
                        "CREATE TRIGGER reject_block_edit BEFORE UPDATE ON unavailableTimes BEGIN SELECT RAISE(ABORT, 'test failure'); END"
                )
                try db.execute(
                    sql:
                        "CREATE TRIGGER reject_block_delete BEFORE DELETE ON unavailableTimes BEGIN SELECT RAISE(ABORT, 'test failure'); END"
                )
            }
            var didFinish = false
            let (edit, editModel) = try editingSession(block) { _ in didFinish = true }
            editModel.draft.label = "Travel"
            #expect(!(await edit.save()))
            #expect(!(await edit.delete()))
            #expect(!didFinish)
            #expect(!edit.isWorking)
            #expect(
                try await database.read { db in
                    try UnavailableTimeRecord.find(recordID).fetchOne(db)?.unavailableTime
                } == block)
            #expect(
                try await database.read { db in
                    try UnavailableTimeCalendarSyncRecord.where {
                        $0.unavailableTimeID.eq(recordID)
                    }.fetchOne(db)?.revision
                } == 1)
        }
    }

    private func creatingSession(
        start: Date, durationMinutes: Int, onFinished: @escaping (Date) -> Void
    ) throws -> (ScheduleEditorSession, UnavailableTimeEditorModel) {
        let session = try #require(
            ScheduleEditorSession(
                request: .scheduleCreation(ScheduleCreationRequest()), selectedDate: start,
                appointments: [], onFinished: onFinished))
        session.selectType(.unavailableTime)
        let model = try unavailableModel(session)
        model.draft.start = start
        model.draft.durationMinutes = durationMinutes
        return (session, model)
    }

    private func editingSession(
        _ block: UnavailableTime, onFinished: @escaping (Date) -> Void
    ) throws -> (ScheduleEditorSession, UnavailableTimeEditorModel) {
        let session = try #require(
            ScheduleEditorSession(
                request: .unavailableTimeEditor(UnavailableTimeEditorRequest(block: block)),
                selectedDate: block.start, appointments: [], onFinished: onFinished))
        return (session, try unavailableModel(session))
    }

    private func unavailableModel(_ session: ScheduleEditorSession) throws
        -> UnavailableTimeEditorModel
    {
        guard case .unavailableTime(let model) = session.editor else {
            throw UnavailableTimeError.missingRecord
        }
        return model
    }
    private func makeDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        try migrateDatabase(database)
        return database
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func instant(_ string: String) throws -> Date {
        try Date(string, strategy: .iso8601)
    }
}
