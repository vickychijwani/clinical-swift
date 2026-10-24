import ClinicalModels
import Testing

@testable import clinical_swift

struct PatientDraftTests {
    @Test func normalizesNameCaseAndSpacingForSave() {
        #expect(PatientDraft.normalizedName("  genelia   d'souza  ") == "Genelia D'Souza")
        #expect(PatientDraft.normalizedName("MARY ANN") == "Mary Ann")
        #expect(PatientDraft.normalizedName("anne-marie o’neill") == "Anne-Marie O’Neill")
        #expect(PatientDraft.normalizedName("   ") == nil)
    }

    @Test func patientNameAssignmentPreservesEditableInputUntilNormalized() {
        let draft = PatientDraft(name: "  genelia   d'souza  ")

        #expect(draft.name == "  genelia   d'souza  ")
        #expect(draft.normalized.name == "Genelia D'Souza")
    }

    @Test func stripsContactBookkeepingPrefixesCaseInsensitively() {
        #expect(PatientDraft.prefilledName(fromContactName: "Patient Aarav Mehta") == "Aarav Mehta")
        #expect(
            PatientDraft.prefilledName(fromContactName: "WEBSITE LEAD Anjali Desai")
                == "Anjali Desai")
        #expect(PatientDraft.prefilledName(fromContactName: "lead Mary Ann") == "Mary Ann")
        #expect(
            PatientDraft.prefilledName(fromContactName: "lead genelia d'souza")
                == "genelia d'souza")
    }

    @Test func preservesContactNamesWithoutBookkeepingPrefixes() {
        #expect(PatientDraft.prefilledName(fromContactName: "Aarav Mehta") == "Aarav Mehta")
    }

    @Test func doesNotPrefillPatientCalledContacts() {
        #expect(PatientDraft.prefilledName(fromContactName: "Patient Called For Cleaning") == nil)
        #expect(PatientDraft.prefilledName(fromContactName: "patient called about pain") == nil)
    }

    @Test func doesNotOverwriteExistingPatientName() {
        var draft = PatientDraft(name: "Existing Name")

        draft.prefillName(fromContactName: "Patient New Name")

        #expect(draft.name == "Existing Name")
    }
}
