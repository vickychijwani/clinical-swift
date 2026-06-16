import Foundation

nonisolated struct PatientDraft: Equatable, Sendable {
    var name: String?
    var phone: String?
    var dob: Date?
    var gender: Gender?

    init(
        name: String? = nil,
        phone: String? = nil,
        dob: Date? = nil,
        gender: Gender? = nil
    ) {
        self.name = name
        self.phone = phone
        self.dob = dob
        self.gender = gender
    }

    init(patient: Patient?) {
        self.init(
            name: patient?.name,
            phone: patient?.phone,
            dob: patient?.dob,
            gender: patient?.gender
        )
    }

    var normalized: PatientDraft {
        PatientDraft(
            name: name?.nilIfBlank,
            phone: phone?.nilIfBlank,
            dob: dob,
            gender: gender
        )
    }

    func makePatient(id: UUID = UUID()) -> Patient {
        Patient(
            id: id,
            name: name?.nilIfBlank,
            phone: phone?.nilIfBlank,
            dob: dob,
            gender: gender
        )
    }
}
