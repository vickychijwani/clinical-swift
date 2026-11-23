import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData

@MainActor @Observable
final class PatientEditorModel {
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.telemetry) private var telemetry

    private let editedPatient: Patient?
    private let originalDraft: PatientDraft

    private(set) var isSaving = false
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
        if draft.phone?.nilIfBlank != nil, draft.normalized.phone == nil {
            return true
        }
        return draft.normalized != originalDraft
    }

    func save() async -> Patient? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        saveErrorMessage = nil
        let normalizedDraft = draft.normalized

        if draft.phone?.nilIfBlank != nil, normalizedDraft.phone == nil {
            saveErrorMessage = "Invalid phone number"
            return nil
        }

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

            telemetry.event(
                category: .patient,
                name: editedPatient == nil ? "patient_created" : "patient_updated",
                recordID: patient.id.uuidString.lowercased(),
                action: editedPatient == nil ? "create" : "edit"
            )
            return patient
        } catch is PatientEditingError {
            saveErrorMessage = "Save failed"
            telemetry.log(
                .error,
                category: .patient,
                name: "patient_save_failed",
                message: "This patient can no longer be edited.",
                error: PatientEditingError.unavailable,
                recordID: patient.id.uuidString.lowercased(),
                action: editedPatient == nil ? "create" : "edit"
            )
            return nil
        } catch {
            saveErrorMessage = "Save failed"
            telemetry.log(
                .error,
                category: .patient,
                name: "patient_save_failed",
                message: "The patient could not be saved.",
                error: error,
                recordID: patient.id.uuidString.lowercased(),
                action: editedPatient == nil ? "create" : "edit"
            )
            return nil
        }
    }

    static func savePhone(_ rawPhone: String, for patient: Patient) async -> PatientPhoneSaveResult
    {
        guard let normalizedPhone = PhoneNumber.normalizedE164(rawPhone) else {
            return .invalidPhone
        }
        if normalizedPhone == PhoneNumber.normalizedE164(patient.phone) {
            return .unchanged
        }

        let editorModel = PatientEditorModel(patient: patient)
        editorModel.draft.phone = normalizedPhone
        guard let saved = await editorModel.save() else {
            return .failed
        }
        return .saved(saved)
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }
}

nonisolated enum PatientPhoneSaveResult: Equatable, Sendable {
    case saved(Patient)
    case unchanged
    case invalidPhone
    case failed
}

nonisolated enum PatientEditingError: Error {
    case unavailable
}
