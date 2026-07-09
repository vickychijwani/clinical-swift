import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct PatientEditorModelTests {
    @Test func editInitializationPreservesValuesAndTracksChanges() {
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let patient = Patient(
            name: "Aarav Mehta",
            phone: "+919820144532",
            dob: createdAt,
            gender: .male,
            createdDate: createdAt
        )

        let model = PatientEditorModel(patient: patient)

        #expect(model.title == "Edit Patient")
        #expect(model.draft == PatientDraft(patient: patient))
        #expect(!model.hasUnsavedChanges)

        model.draft.name = "Aarav Shah"
        #expect(model.hasUnsavedChanges)
    }

    @Test func editingUpdatesMutableFieldsAndPreservesIdentityAndCreationDate() async throws {
        let database = try testDatabase()
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let patient = Patient(
            name: "Aarav Mehta",
            phone: "+919820144532",
            createdDate: createdAt
        )
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: createdAt) }
                .execute(db)
        }

        let savedPatient = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = updatedAt
        } operation: {
            let model = PatientEditorModel(patient: patient)
            model.draft.name = "Aarav Shah"
            model.draft.phone = "98201 44533"
            model.draft.gender = .other
            return await model.save()
        }

        let record = try await database.read { db in
            try PatientRecord.find(patient.id).fetchOne(db)
        }
        #expect(savedPatient?.id == patient.id)
        #expect(savedPatient?.name == "Aarav Shah")
        #expect(savedPatient?.phone == "+919820144533")
        #expect(savedPatient?.gender == .other)
        #expect(savedPatient?.createdDate == createdAt)
        #expect(record?.id == patient.id)
        #expect(record?.name == "Aarav Shah")
        #expect(record?.phone == "+919820144533")
        #expect(record?.gender == Gender.other.storageValue)
        #expect(record?.createdAt == createdAt)
        #expect(record?.updatedAt == updatedAt)
    }

    @Test func missingPatientRemainsInEditorWithUnavailableError() async throws {
        let database = try testDatabase()
        let patient = Patient(name: "Aarav Mehta")

        let result = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSinceReferenceDate: 2_000)
        } operation: {
            let model = PatientEditorModel(patient: patient)
            let savedPatient = await model.save()
            return (savedPatient, model.saveErrorMessage)
        }

        #expect(result.0 == nil)
        #expect(result.1 == "This patient can no longer be edited.")
    }

    @Test func creationStillNormalizesAndPersistsPatient() async throws {
        let database = try testDatabase()
        let now = Date(timeIntervalSinceReferenceDate: 2_000)

        let savedPatient = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = now
        } operation: {
            let model = PatientEditorModel()
            model.draft.name = "  Aarav Mehta  "
            model.draft.phone = "98201 44532"
            return await model.save()
        }

        let record = try await database.read { db in
            try PatientRecord.all.fetchOne(db)
        }
        #expect(savedPatient?.name == "Aarav Mehta")
        #expect(savedPatient?.phone == "+919820144532")
        #expect(savedPatient?.createdDate == now)
        #expect(record?.name == "Aarav Mehta")
        #expect(record?.phone == "+919820144532")
        #expect(record?.createdAt == now)
        #expect(record?.updatedAt == now)
    }

    @Test func creationWithInitialDraftReturnsSavedPatientAndPersistsSameIdentity() async throws {
        let database = try testDatabase()
        let now = Date(timeIntervalSinceReferenceDate: 3_000)

        let savedPatient = await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = now
        } operation: {
            let model = PatientEditorModel(
                initialDraft: PatientDraft(
                    name: "  Meera Iyer  ",
                    phone: "98201 44534"
                )
            )
            return await model.save()
        }

        #expect(savedPatient?.name == "Meera Iyer")
        #expect(savedPatient?.phone == "+919820144534")
        #expect(savedPatient?.createdDate == now)

        guard let savedPatient else { return }
        let record = try await database.read { db in
            try PatientRecord.find(savedPatient.id).fetchOne(db)
        }
        #expect(record?.id == savedPatient.id)
        #expect(record?.name == savedPatient.name)
        #expect(record?.phone == savedPatient.phone)
        #expect(record?.createdAt == savedPatient.createdDate)
        #expect(record?.updatedAt == now)
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }
}
