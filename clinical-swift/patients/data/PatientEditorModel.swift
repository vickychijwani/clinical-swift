import ClinicalModels
import ClinicalPersistence
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

    init(patient: Patient? = nil, initialDraft: PatientDraft = PatientDraft()) {
        let draft: PatientDraft
        if let patient {
            draft = PatientDraft(patient: patient)
        } else {
            draft = initialDraft
        }
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

    func save() async -> Patient? {
        saveErrorMessage = nil
        let normalizedDraft = draft.normalized

        let patient = Patient(
            id: editedPatient?.id ?? UUID(),
            name: normalizedDraft.name,
            phone: normalizedDraft.phone,
            dob: normalizedDraft.dob,
            gender: normalizedDraft.gender,
            createdDate: editedPatient?.createdDate ?? now
        )

        do {
            try patient.validate()
        } catch Patient.ValidationError.missingNameAndPhone {
            saveErrorMessage = "Enter a name or phone number."
            return nil
        } catch {
            saveErrorMessage = "Check the patient details and try again."
            return nil
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

            return patient
        } catch is PatientEditingError {
            saveErrorMessage = "This patient can no longer be edited."
            return nil
        } catch {
            saveErrorMessage = "The patient could not be saved."
            return nil
        }
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }
}

nonisolated enum PatientEditingError: Error {
    case unavailable
}
