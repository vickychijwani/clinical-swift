import ClinicalModels
import Foundation
import SQLiteData

@Table("patients")
public nonisolated struct PatientRecord: Identifiable, Sendable {
    public let id: UUID
    public var name: String?
    public var phone: String?
    public var dob: Date?
    public var gender: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
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
        self.phone = PhoneNumber.normalizedE164(phone)
        self.dob = dob
        self.gender = gender?.nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(_ patient: Patient, now: Date = .now) {
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
    public nonisolated init(_ record: PatientRecord) {
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
    public nonisolated init?(storageValue: String) {
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

    public nonisolated var storageValue: String {
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
