import ClinicalModels
import ClinicalPersistence
import Testing

struct PatientNameSearchTests {
    @Test func matchesPrefixOfAnyNameWord() {
        #expect(PatientNameSearch.matches("Anjali Desai", searchText: "an"))
        #expect(PatientNameSearch.matches("Mary Ann", searchText: "an"))
        #expect(!PatientNameSearch.matches("Rani Dutta", searchText: "an"))
    }

    @Test func matchesMultipleWordPrefixesInAnyOrder() {
        #expect(PatientNameSearch.matches("Anjali Desai", searchText: "an de"))
        #expect(PatientNameSearch.matches("Della Ann", searchText: "an de"))
        #expect(!PatientNameSearch.matches("Anjali Dutta", searchText: "an de"))
    }

    @Test func blankSearchMatchesNamesAndUnknownPatients() {
        #expect(PatientNameSearch.matches("Anjali Desai", searchText: " "))
        #expect(PatientNameSearch.matches(nil, searchText: " "))
    }

    @Test func nonblankSearchDoesNotMatchUnknownPatients() {
        #expect(!PatientNameSearch.matches(nil, searchText: "an"))
    }
}
