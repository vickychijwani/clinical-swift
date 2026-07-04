import Testing

@testable import clinical_swift

struct PatientDraftTests {
    @Test func stripsContactBookkeepingPrefixesCaseInsensitively() {
        #expect(PatientDraft.prefilledName(fromContactName: "Patient Aarav Mehta") == "Aarav Mehta")
        #expect(PatientDraft.prefilledName(fromContactName: "WEBSITE LEAD Anjali Desai") == "Anjali Desai")
        #expect(PatientDraft.prefilledName(fromContactName: "lead Mary Ann") == "Mary Ann")
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
