import Foundation
import SQLiteData

@Table("patients")
nonisolated struct PatientRecord: Identifiable, Sendable {
    let id: UUID
    var name: String?
    var phone: String?
    var dob: Date?
    var gender: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String?,
        phone: String?,
        dob: Date?,
        gender: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name?.nilIfBlank
        self.phone = phone?.nilIfBlank
        self.dob = dob
        self.gender = gender?.nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(_ patient: Patient, now: Date = .now) {
        self.init(
            id: patient.id,
            name: patient.name,
            phone: patient.phone,
            dob: patient.dob,
            gender: patient.gender?.storageValue,
            createdAt: patient.createdDate,
            updatedAt: now
        )
    }
}

extension Patient {
    nonisolated init(_ record: PatientRecord) {
        self.init(
            id: record.id,
            name: record.name,
            phone: record.phone,
            dob: record.dob,
            gender: record.gender.flatMap(Gender.init(storageValue:)),
            createdDate: record.createdAt
        )
    }
}

extension Gender {
    nonisolated init?(storageValue: String) {
        switch storageValue {
        case Self.female.storageValue:
            self = .female
        case Self.male.storageValue:
            self = .male
        case Self.other.storageValue:
            self = .other
        default:
            return nil
        }
    }

    nonisolated var storageValue: String {
        switch self {
        case .female:
            "female"
        case .male:
            "male"
        case .other:
            "other"
        }
    }
}
