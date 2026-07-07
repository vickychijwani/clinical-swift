import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable
final class PatientEditorModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now

    private let editedPatient: Patient?
    private let originalDraft: PatientDraft

    var draft: PatientDraft
    private(set) var saveErrorMessage: String?

    init(patient: Patient? = nil) {
        let draft = PatientDraft(patient: patient)
        self.editedPatient = patient
        self.originalDraft = draft.normalized
        self.draft = draft
    }

    var title: String {
        editedPatient == nil ? "New Patient" : "Edit Patient"
    }

    var hasUnsavedChanges: Bool {
        draft.normalized != originalDraft
    }

    func save() async -> Bool {
        saveErrorMessage = nil

        let patient = Patient(
            id: editedPatient?.id ?? UUID(),
            name: draft.name,
            phone: draft.phone,
            dob: draft.dob,
            gender: draft.gender,
            createdDate: editedPatient?.createdDate ?? now
        )

        do {
            try patient.validate()
        } catch Patient.ValidationError.missingNameAndPhone {
            saveErrorMessage = "Enter a name or phone number."
            return false
        } catch {
            saveErrorMessage = "Check the patient details and try again."
            return false
        }

        do {
            if let editedPatient {
                let patientID = editedPatient.id
                let name = patient.name
                let phone = patient.phone
                let dob = patient.dob
                let gender = patient.gender?.storageValue
                let updatedAt = now

                try await database.write { db in
                    guard try PatientRecord.find(patientID).fetchOne(db) != nil else {
                        throw PatientEditingError.unavailable
                    }

                    try PatientRecord.find(patientID)
                        .update {
                            $0.name = name
                            $0.phone = phone
                            $0.dob = dob
                            $0.gender = gender
                            $0.updatedAt = updatedAt
                        }
                        .execute(db)
                }
            } else {
                let record = PatientRecord(patient, now: now)
                try await database.write { db in
                    try PatientRecord.insert { record }
                        .execute(db)
                }
            }

            return true
        } catch is PatientEditingError {
            saveErrorMessage = "This patient can no longer be edited."
            return false
        } catch {
            saveErrorMessage = "The patient could not be saved."
            return false
        }
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }
}

nonisolated enum PatientEditingError: Error {
    case unavailable
}
