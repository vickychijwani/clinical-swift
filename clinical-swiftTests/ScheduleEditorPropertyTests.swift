import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct ScheduleEditorPropertyTests {
    @Test func holdInsideBreakReturnsToItsTouchOrigin() throws {
        let day = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        withDependencies {
            $0.date.now = day
        } operation: {
            let session = ScheduleEditorSession(
                bookingID: UUID(), selectedDate: day, center: TimeOfDay(15, 59), items: []
            ) { _ in }
            let original = session.preview
            // Moving back to the touch origin must restore the chosen interval.
            let outwardCorrection = session.updateAdjustment(translation: -10, items: [])
            let returnCorrection = session.updateAdjustment(translation: 0, items: [])
            #expect(outwardCorrection == 0)
            #expect(returnCorrection == 0)
            let actualMinute = Int(session.preview.start.timeIntervalSince(day) / 60)
            let details =
                "Returning to the touch origin must restore 15:45 (minute 945); actual minute=\(actualMinute)."
            #expect(session.preview.start == original.start, "\(details)")
            #expect(session.preview.durationMinutes == original.durationMinutes)
        }
    }

    @Test(arguments: [UInt64(0xED17_0001), 0xED17_0002, 0xED17_0003, 0xED17_0004])
    func generatedCreationHistories(seed: UInt64) async throws {
        var generator = Generator(state: seed)
        for trial in 0..<8 {
            let hold = trial.isMultiple(of: 2)
            let centers = [(540, 540), (548, 540), (780, 765), (959, 945), (1260, 1230)]
            let (center, initialMinute) = centers[generator.integer(centers.count)]
            let actions = generator.history(unavailable: trial % 4 < 2, discard: trial % 3 == 0)
            if let failure = try await replay(
                actions, hold: hold, center: center, initialMinute: initialMinute)
            {
                let reduced = try await reduce(
                    actions, failure: failure.check, hold: hold, center: center,
                    initialMinute: initialMinute)
                let details =
                    "seed=\(seed), trial=\(trial), hold=\(hold), center=\(center), "
                    + "check=\(failure.check), step=\(failure.step)\n"
                    + "\(failure.details)\ntrace=\(actions)\nreduced=\(reduced)"
                if let reducedFailure = try await replay(
                    reduced, hold: hold, center: center, initialMinute: initialMinute)
                {
                    Issue.record("\(details)\nreduced details=\(reducedFailure.details)")
                } else {
                    Issue.record("\(details)")
                }
                return
            }
        }
    }

    private nonisolated enum Action: Equatable, CustomStringConvertible {
        case type(Bool)
        case patient(Int)
        case label(String)
        case sheet(Bool)
        case day(Int)
        case begin(resize: Bool)
        case travel(Int)
        case release
        case fail(Bool)
        case save, saveTwice, discard

        var description: String {
            switch self {
            case .type(let block): "type(\(block ? "block" : "appointment"))"
            case .patient(let index): "patient(\(index))"
            case .label(let text): "label(\(String(reflecting: text)))"
            case .sheet(let shown): "sheet(\(shown))"
            case .day(let offset): "day(\(offset))"
            case .begin(let resize): "begin(\(resize ? "resize" : "move"))"
            case .travel(let direction): "travel(\(direction * 10000)pt)"
            case .release: "release"
            case .fail(let enabled): "fail(\(enabled))"
            case .save: "save"
            case .saveTwice: "saveTwice"
            case .discard: "discard"
            }
        }
    }

    private struct Model {
        var unavailable = false
        var day = 0
        var minute: Int
        var duration = 30
        var patient: Int?
        var label = ""
        var sheet: Bool
        var drag: (minute: Int, duration: Int, resize: Bool)?
        var rejectsWrites = false
        var error = false
        var finished = false
        var saved = false

        mutating func apply(_ action: Action) -> Int? {
            if case .fail(let enabled) = action {
                rejectsWrites = enabled
                return nil
            }
            // Bindings and release callbacks can still arrive while a finished view closes.
            if case .sheet(let value) = action {
                sheet = value
                return nil
            }
            if case .label(let value) = action {
                if unavailable { label = value }
                return nil
            }
            if action == .release {
                drag = nil
                sheet = true
                return nil
            }
            guard !finished else {
                return action == .save || action == .saveTwice ? 0 : nil
            }
            switch action {
            case .type(let value):
                if value != unavailable {
                    unavailable = value
                    patient = nil
                    label = ""
                    drag = nil
                    error = false
                }
            case .patient(let index):
                if !unavailable {
                    patient = index
                    sheet = false
                }
            case .label(let text):
                if unavailable { label = text }
            case .sheet(let value): sheet = value
            case .day(let value):
                if drag == nil { day = value }
            case .begin(let resize):
                if drag == nil { drag = (minute, duration, resize) }
            case .travel(let direction):
                // Extreme travel has a known boundary result, independent of display geometry.
                if let drag {
                    if direction == 0 {
                        minute = drag.minute
                        duration = drag.duration
                    } else if drag.resize {
                        minute = drag.minute
                        duration = direction < 0 ? 15 : 1260 - drag.minute
                    } else {
                        minute = direction < 0 ? 540 : 1260 - drag.duration
                        duration = drag.duration
                    }
                }
            case .release:
                drag = nil
                sheet = true
            case .save, .saveTwice:
                drag = nil
                if !unavailable, patient == nil {
                    sheet = true
                    return 0
                }
                error = rejectsWrites
                if rejectsWrites { return 0 }
                finished = true
                saved = true
                return 1
            case .discard:
                drag = nil
                finished = true
            case .fail: break
            }
            return nil
        }
    }

    private struct Failure {
        let check: String
        let step: Int
        var details = ""
    }

    private func replay(
        _ actions: [Action], hold: Bool, center: Int, initialMinute: Int
    ) async throws -> Failure? {
        // Each replay gets a real SQLite database. No production save method is stubbed.
        let database = try testDatabase()
        let day = try Date("2026-10-02T00:00:00+05:30", strategy: .iso8601)
        let patients = [
            Patient(name: "Aarav", createdDate: day), Patient(name: "Diya", createdDate: day),
        ]
        try await database.write { db in
            for patient in patients {
                try PatientRecord.insert { PatientRecord(patient, now: day) }.execute(db)
            }
        }
        return try await withDependencies {
            $0.date.now = day
            $0.defaultDatabase = database
        } operation: {
            var completions: [ScheduleEditorSession.Completion] = []
            let session: ScheduleEditorSession
            if hold {
                session = ScheduleEditorSession(
                    bookingID: UUID(), selectedDate: day,
                    center: TimeOfDay(center / 60, center % 60), items: []
                ) { completions.append($0) }
            } else {
                session = ScheduleEditorSession(
                    request: .create(), selectedDate: day, appointments: []
                ) { completions.append($0) }
            }
            var model = Model(minute: hold ? initialMinute : 540, sheet: !hold)
            if hold { model.drag = (model.minute, 30, false) }
            var previousID = session.preview.id
            for step in -1..<actions.count {
                let action = step >= 0 ? actions[step] : nil
                let oldType = model.unavailable
                let expectedSaves = action.flatMap { model.apply($0) }
                let actualSaves: Int?
                if let action {
                    actualSaves = try await perform(
                        action, on: session, patients: patients, database: database, day: day)
                } else {
                    actualSaves = nil
                }
                if actualSaves != expectedSaves { return Failure(check: "save result", step: step) }
                let changedType = oldType != model.unavailable
                if (session.preview.id != previousID) != changedType {
                    return Failure(check: "draft identity", step: step)
                }
                previousID = session.preview.id
                if let check = mismatch(
                    session, model: model, patients: patients, day: day, completions: completions)
                {
                    let expected = day.addingTimeInterval(
                        Double(model.day * 86400 + model.minute * 60))
                    return Failure(
                        check: check, step: step,
                        details: "expected start=\(expected), duration=\(model.duration); "
                            + "actual start=\(session.preview.start), duration=\(session.preview.durationMinutes)"
                    )
                }
                let records = try await database.read { db in
                    (
                        try AppointmentRecord.fetchAll(db), try UnavailableTimeRecord.fetchAll(db),
                        try PatientRecord.count().fetchOne(db)
                    )
                }
                if records.0.count != (model.saved && !model.unavailable ? 1 : 0)
                    || records.1.count != (model.saved && model.unavailable ? 1 : 0)
                    || records.2 != 2
                {
                    return Failure(check: "only active draft commits once", step: step)
                }
                let start = day.addingTimeInterval(Double(model.day * 86400 + model.minute * 60))
                if let record = records.0.first {
                    guard let patient = model.patient else {
                        return Failure(check: "stored patient", step: step)
                    }
                    if session.preview.id != .appointment(record.id)
                        || record.patientID != patients[patient].id
                        || record.start != start || record.durationMinutes != model.duration
                        || record.status != Appointment.Status.scheduled.rawValue
                    {
                        return Failure(check: "stored appointment", step: step)
                    }
                }
                if let record = records.1.first {
                    let label = model.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    if session.preview.id != .unavailableTime(record.id) || record.start != start
                        || record.durationMinutes != model.duration
                        || record.label != (label.isEmpty ? nil : label)
                    {
                        return Failure(check: "stored unavailable time", step: step)
                    }
                }
            }
            return nil
        }
    }

    private func mismatch(
        _ session: ScheduleEditorSession, model: Model, patients: [Patient], day: Date,
        completions: [ScheduleEditorSession.Completion]
    ) -> String? {
        let date = day.addingTimeInterval(Double(model.day * 86400))
        let start = date.addingTimeInterval(Double(model.minute * 60))
        if session.preview.start != start || session.preview.durationMinutes != model.duration
            || session.selectedDate != date
        {
            return "interval"
        }
        if (session.itemType == .unavailableTime) != model.unavailable { return "active type" }
        if session.adjustment.isDragging != (model.drag != nil) { return "drag lifetime" }
        if session.isShowingSheet != model.sheet { return "fields sheet" }
        if session.didFinish != model.finished || session.isWorking
            || session.allowsDateSelection == model.finished
        {
            return "session lifetime"
        }
        if (session.errorMessage != nil) != model.error { return "save error" }
        switch session.editor {
        case .appointment(let editor):
            if editor.draft.selectedPatient?.id != model.patient.map({ patients[$0].id })
                || editor.draft.selectedDate != date
            {
                return "patient or draft date"
            }
        case .unavailableTime(let editor):
            if editor.draft.label != model.label { return "label" }
        }
        if completions.count != (model.finished ? 1 : 0) { return "completion count" }
        if let completion = completions.first {
            switch completion {
            case .discarded(let finishedDate):
                if model.saved || finishedDate != date { return "discard completion" }
            case .unavailableTimeChanged(let finishedDate):
                if !model.saved || !model.unavailable || finishedDate != start {
                    return "block completion"
                }
            case .appointmentSaved(let saved):
                if !model.saved || model.unavailable || saved.start != start
                    || saved.kind != .booked
                    || session.preview.id != .appointment(saved.id)
                {
                    return "appointment completion"
                }
            }
        }
        if session.visibleItems([], for: date).map(\.id) != [session.preview.id]
            || !session.visibleItems([], for: date.addingTimeInterval(86400)).isEmpty
        {
            return "draft page membership"
        }
        return nil
    }

    private func perform(
        _ action: Action, on session: ScheduleEditorSession, patients: [Patient],
        database: DatabaseQueue, day: Date
    ) async throws -> Int? {
        switch action {
        case .type(let unavailable):
            session.selectType(unavailable ? .unavailableTime : .appointment)
        case .patient(let index): session.selectPatient(patients[index])
        case .label(let text):
            if case .unavailableTime(let model) = session.editor { model.draft.label = text }
        case .sheet(let value): session.isShowingSheet = value
        case .day(let offset): session.selectDate(day.addingTimeInterval(Double(offset * 86400)))
        case .begin(let resize):
            session.beginAdjustment(session.preview, edge: resize ? .duration : .move, items: [])
        case .travel(let direction):
            session.updateAdjustment(translation: CGFloat(direction * 10000), items: [])
        case .release: session.releaseBooking(session.adjustment)
        case .fail(let enabled):
            try await database.write { db in
                for table in ["appointments", "unavailableTimes"] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS reject_property_\(table)")
                    if enabled {
                        try db.execute(
                            sql: """
                                CREATE TRIGGER reject_property_\(table) BEFORE INSERT ON \(table)
                                BEGIN SELECT RAISE(ABORT, 'property failure'); END
                                """)
                    }
                }
            }
        case .save: return await session.save() ? 1 : 0
        case .saveTwice:
            let first = Task { await session.save() }
            let second = Task { await session.save() }
            return await [first.value, second.value].filter { $0 }.count
        case .discard: session.discard()
        }
        return nil
    }

    private func reduce(
        _ actions: [Action], failure: String, hold: Bool, center: Int, initialMinute: Int
    ) async throws -> [Action] {
        var result = actions
        var width = max(result.count / 2, 1)
        var attempts = 0
        // Bound failure work. Retain only reductions that reproduce the same check.
        while width > 0, attempts < 32 {
            var index = 0
            while index + width <= result.count, attempts < 32 {
                var candidate = result
                candidate.removeSubrange(index..<(index + width))
                attempts += 1
                if try await replay(
                    candidate, hold: hold, center: center, initialMinute: initialMinute)?
                    .check == failure
                {
                    result = candidate
                } else {
                    index += width
                }
            }
            width /= 2
        }
        return result
    }

    private struct Generator {
        var state: UInt64

        mutating func integer(_ count: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 16) % UInt64(count))
        }

        mutating func history(unavailable: Bool, discard: Bool) -> [Action] {
            var actions: [Action] = [.day(1), .save, .release, .patient(integer(2)), .sheet(true)]
            for _ in 0..<18 {
                let choices: [Action] = [
                    .type(integer(2) == 0), .patient(integer(2)),
                    .label(["Travel", "  Clinic meeting  ", "  "][integer(3)]),
                    .sheet(integer(2) == 0), .day(integer(5) - 2),
                    .begin(resize: integer(2) == 0), .travel(integer(3) - 1), .release,
                ]
                actions.append(choices[integer(choices.count)])
            }
            // Directed segments ensure useful failures, field clearing, and terminal calls in every run.
            actions += [
                .type(true), .label("Travel"), .type(false), .patient(integer(2)),
                .type(true), .type(false), .save, .type(unavailable), .patient(integer(2)),
                .begin(resize: integer(2) == 0), .travel(integer(2) == 0 ? -1 : 1),
                .fail(true), .save, .fail(false), .release, .day(integer(5) - 2),
                .sheet(false), .sheet(true), discard ? .discard : .saveTwice,
                .type(!unavailable), .patient(integer(2)), .day(7),
                .begin(resize: true), .travel(-1), .saveTwice, .discard,
            ]
            return actions
        }
    }
}
