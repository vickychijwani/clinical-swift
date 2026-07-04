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
            phone: PhoneNumber.normalizedE164(phone),
            dob: dob,
            gender: gender
        )
    }

    static func prefilledName(fromContactName contactName: String?) -> String? {
        guard let contactName = contactName?.nilIfBlank else { return nil }

        let lowercaseName = contactName.lowercased()
        guard !lowercaseName.hasPrefix("patient called ") else { return nil }

        let removablePrefixes = ["patient ", "website lead ", "lead "]
        for prefix in removablePrefixes where lowercaseName.hasPrefix(prefix) {
            return String(contactName.dropFirst(prefix.count)).nilIfBlank
        }

        return contactName
    }

    mutating func prefillName(fromContactName contactName: String?) {
        guard name?.nilIfBlank == nil else { return }
        name = Self.prefilledName(fromContactName: contactName)
    }

    func makePatient(id: UUID = UUID()) -> Patient {
        Patient(
            id: id,
            name: name?.nilIfBlank,
            phone: PhoneNumber.normalizedE164(phone),
            dob: dob,
            gender: gender
        )
    }
}
