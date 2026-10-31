import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentCompletionInterruptionTests {
    private enum Interruption: CaseIterable { case sheet, sameRoot, date, destination }

    @Test(arguments: Interruption.allCases)
    private func pendingSaveKeepsOneOwnerAndCannotDismissAnInterruption(
        _ interruption: Interruption
    ) async throws {
        let fixture = try makeFixture()
        let gate = CompletionWriteGate()
        defer { gate.release() }
        try await fixture.database.write { db in
            db.add(
                function: DatabaseFunction("wait_for_completion", argumentCount: 0) { _ in
                    gate.wait()
                    return 0
                })
            try db.execute(
                sql: """
                    CREATE TEMP TRIGGER hold_completion BEFORE UPDATE OF status ON appointments
                    BEGIN SELECT wait_for_completion(); END
                    """)
        }
        try await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.calendar = FinancialDate.calendar
            $0.date.now = fixture.timestamp
        } operation: {
            let router = Router(selectedScheduleDate: fixture.timestamp)
            router.presentDetails(.appointment(fixture.details.id))
            let presentation = try #require(router.detailsPresentation)
            router.presentationDidAppear(presentation.id)
            let visit = UUID()
            router.beginAppointmentCompletion(
                fixture.details, visitID: visit, presentationID: presentation.id)
            let model = try #require(presentation.completionDrafts[visit])
            model.setAmountText("1000")
            model.selectMethod(.upi)
            let saving = Task { await model.save() }
            let deadline = ContinuousClock.now + .seconds(3)
            while !gate.isWaiting && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(gate.isWaiting)
            #expect(model.isSaving)
            #expect(presentation.isSavingCompletion)
            router.setDetailsPath([], presentationID: presentation.id)
            #expect(presentation.currentRoute == .appointmentCompletion(visit))
            model.setAmountText("2000")
            model.selectMethod(.card)
            #expect(model.amountText == "1000")
            #expect(model.paymentMethod == .upi)
            #expect(await model.save() == false)

            switch interruption {
            case .sheet: router.requestScheduleCreation()
            case .sameRoot:
                router.presentDetails(.appointment(fixture.details.id))
                router.beginAppointmentCompletion(
                    fixture.details, visitID: visit, presentationID: presentation.id)
                #expect(presentation.completionDrafts[visit] !== model)
            case .date: router.selectScheduleDate(fixture.timestamp.addingTimeInterval(86400))
            case .destination: router.pushDetails(.patient(fixture.details.patient.id))
            }
            gate.release()
            #expect(await saving.value)
            router.finishAppointmentCompletion(model, presentationID: presentation.id)
            switch interruption {
            case .sheet:
                #expect(router.detailsPresentation == nil)
                router.presentationDidDismiss()
                #expect(router.scheduleCreationRequest != nil)
            case .sameRoot:
                #expect(router.detailsPresentation === presentation)
                #expect(presentation.currentRoute == .appointmentCompletion(visit))
                let replacement = try #require(presentation.completionDrafts[visit])
                #expect(await replacement.save() == false)
                #expect(replacement.errorMessage == "This appointment is no longer scheduled.")
            case .date:
                #expect(router.detailsPresentation == nil)
                #expect(
                    router.selectedScheduleDate
                        == FinancialDate.day(fixture.timestamp.addingTimeInterval(86400)))
            case .destination:
                #expect(presentation.currentRoute == .patient(fixture.details.patient.id))
                #expect(router.detailsPresentation === presentation)
            }
            let records = try await fixture.database.read { db in
                try AccountEntryRecord.all.fetchAll(db)
            }
            #expect(records.count == 2)
            #expect(records.allSatisfy { $0.amount == 1000 })
            let stored = try await fixture.database.read { db in
                try AppointmentRecord.find(fixture.details.id).fetchOne(db)
            }
            #expect(stored?.status == "completed")
        }
    }

    @Test(arguments: ["", "0", "000", "cleared"])
    func noDuesDraftsCreateNoEntries(_ text: String) async throws {
        let fixture = try makeFixture()
        await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.date.now = fixture.timestamp
        } operation: {
            let model = AppointmentCompletionModel(
                id: UUID(), details: fixture.details, originPath: [])
            model.setAmountText("1000")
            model.setAmountText(text == "cleared" ? "" : text)
            model.selectMethod(.card)
            #expect(model.buttonTitle == "No Dues · Complete Appointment")
            #expect(await model.save())
        }
        let records = try await fixture.database.read { db in
            try AccountEntryRecord.all.fetchAll(db)
        }
        #expect(records.isEmpty)
    }

    @Test func formOpenAcrossMidnightUsesTheClinicDayAtSave() async throws {
        let fixture = try makeFixture()
        let before = try Date("2026-10-30T18:25:00Z", strategy: .iso8601)
        let after = try Date("2026-10-30T18:35:00Z", strategy: .iso8601)
        let expectedDay = try Date("2026-10-30T18:30:00Z", strategy: .iso8601)
        await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.date.now = before
        } operation: {
            let model = AppointmentCompletionModel(
                id: UUID(), details: fixture.details, originPath: [])
            model.setAmountText("1000")
            await withDependencies {
                $0.date.now = after
            } operation: {
                #expect(await model.save())
            }
        }
        let records = try await fixture.database.read { db in
            try AccountEntryRecord.all.fetchAll(db)
        }
        #expect(records.count == 2)
        #expect(
            records.allSatisfy {
                $0.entryDate == expectedDay && $0.createdAt == after && $0.updatedAt == after
            })
    }

    @Test(arguments: ["missing", "terminal", "reassigned", "multiple", "credit", "storage"])
    func saveErrorsKeepTheDraftAndAllowCorrectionOrRetry(_ failure: String) async throws {
        let fixture = try makeFixture()
        try await withDependencies {
            $0.defaultDatabase = fixture.database
            $0.date.now = fixture.timestamp
        } operation: {
            try await fixture.database.write { db in
                let id = fixture.details.id
                let patient = fixture.details.patient.id
                switch failure {
                case "missing": try AppointmentRecord.find(id).delete().execute(db)
                case "terminal":
                    try AppointmentRecord.find(id).update { $0.status = "cancelled" }.execute(db)
                case "reassigned":
                    try AppointmentRecord.find(id).update { $0.patientID = fixture.otherPatientID }
                        .execute(db)
                case "multiple", "credit":
                    var entries = [
                        AccountEntry(
                            details: .charge(patientID: patient, appointmentID: id), amount: 1500)
                    ]
                    entries.append(
                        AccountEntry(
                            details: failure == "multiple"
                                ? .charge(patientID: patient, appointmentID: id)
                                : .receipt(source: .patient(patient), paymentMethod: nil),
                            amount: 500))
                    try saveAccountEntries(.init(inserts: entries), in: db)
                default:
                    try db.execute(
                        sql:
                            "CREATE TEMP TRIGGER fail_completion BEFORE UPDATE ON appointments BEGIN SELECT RAISE(ABORT, 'test failure'); END"
                    )
                }
            }
            let model = AppointmentCompletionModel(
                id: UUID(), details: fixture.details, originPath: [])
            model.setAmountText("1000")
            model.selectMethod(.upi)
            #expect(await model.save() == false)
            let messages = [
                "missing": "This appointment is no longer available.",
                "terminal": "This appointment is no longer scheduled.",
                "reassigned": "The patient for this appointment has changed.",
                "multiple":
                    "This appointment has several charges. Complete it after correcting the charges.",
                "credit":
                    "This change would leave the patient with a credit balance. Check the earlier receipts.",
                "storage": "The appointment could not be completed. Please try again.",
            ]
            #expect(model.errorMessage == messages[failure])
            #expect(model.amountText == "1000")
            #expect(model.paymentMethod == .upi)
            #expect(model.canSave)
            model.dismissError()
            #expect(model.errorMessage == nil)
            if failure == "storage" {
                try await fixture.database.write { db in
                    try db.execute(sql: "DROP TRIGGER fail_completion")
                }
                #expect(await model.save())
                #expect(!model.canSave)
            }
        }
    }

    @Test func onlyTheCurrentScheduledAppointmentCanOpenCompletion() throws {
        let fixture = try makeFixture()
        try withDependencies {
            $0.calendar = FinancialDate.calendar
        } operation: {
            let router = Router()
            router.presentDetails(.appointment(fixture.details.id))
            let id = try #require(router.detailsPresentation?.id)
            router.beginAppointmentCompletion(
                fixture.details, visitID: UUID(), presentationID: UUID())
            #expect(router.detailsPresentation?.path.isEmpty == true)
            for status in [Appointment.Status.completed, .cancelled] {
                let terminal = AppointmentDetails(
                    appointment: Appointment(
                        id: fixture.details.id, patientName: "Patient", start: fixture.timestamp,
                        durationMinutes: 30, status: status), patient: fixture.details.patient)
                router.beginAppointmentCompletion(terminal, visitID: UUID(), presentationID: id)
                #expect(router.detailsPresentation?.path.isEmpty == true)
            }
            router.pushDetails(.patient(fixture.details.patient.id))
            router.beginAppointmentCompletion(fixture.details, visitID: UUID(), presentationID: id)
            #expect(router.detailsPresentation?.path == [.patient(fixture.details.patient.id)])
        }
    }

    private func makeFixture() throws -> Fixture {
        let database = try testDatabase()
        let timestamp = try Date("2026-10-30T12:00:00Z", strategy: .iso8601)
        let patient = Patient(name: nil)
        let otherPatientID = UUID()
        let appointment = Appointment(
            patientName: patient.displayName, start: timestamp, durationMinutes: 30,
            status: .scheduled)
        try database.write { db in
            for id in [patient.id, otherPatientID] {
                try PatientRecord.insert {
                    PatientRecord(
                        id: id, name: nil, phone: nil, dob: nil, gender: nil, createdAt: timestamp,
                        updatedAt: timestamp)
                }.execute(db)
            }
            let record = try AppointmentRecord.persisted(
                id: appointment.id, patientID: patient.id, start: timestamp, durationMinutes: 30,
                status: .scheduled, createdAt: timestamp, updatedAt: timestamp)
            try AppointmentRecord.insert { record }.execute(db)
        }
        return Fixture(
            database: database,
            details: AppointmentDetails(appointment: appointment, patient: patient),
            otherPatientID: otherPatientID, timestamp: timestamp)
    }

    private nonisolated struct Fixture: Sendable {
        let database: DatabaseQueue
        let details: AppointmentDetails
        let otherPatientID: UUID
        let timestamp: Date
    }
}

/// Block only the test writer; the main actor remains free to exercise interruptions.
private nonisolated final class CompletionWriteGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var entered = false
    private var released = false

    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }

    func wait() {
        condition.lock()
        defer { condition.unlock() }
        entered = true
        while !released { condition.wait() }
    }

    func release() {
        condition.lock()
        defer { condition.unlock() }
        released = true
        condition.broadcast()
    }
}
