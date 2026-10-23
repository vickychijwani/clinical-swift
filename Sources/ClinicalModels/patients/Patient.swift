import Foundation

public nonisolated struct Patient: Identifiable, Hashable, Sendable {
    public static let unknownDisplayName = PatientDisplayName.unknown

    public let id: UUID
    public let name: String?
    public let phone: String?
    public let dob: Date?
    public let gender: Gender?
    public let createdDate: Date

    public enum ValidationError: Error, Equatable {
        case missingNameAndPhone
    }

    public init(
        id: UUID = UUID(),
        name: String?,
        phone: String? = nil,
        dob: Date? = nil,
        gender: Gender? = nil,
        createdDate: Date = .now
    ) {
        let normalizedName = name?.nilIfBlank
        let normalizedPhone = PhoneNumber.normalizedE164(phone)

        self.id = id
        self.name = normalizedName
        self.phone = normalizedPhone
        self.dob = dob
        self.gender = gender
        self.createdDate = createdDate
    }

    public var displayName: String {
        PatientDisplayName.resolve(name)
    }

    public var isUnknown: Bool {
        name == nil
    }

    public func validate() throws {
        let normalizedName = name?.nilIfBlank
        let normalizedPhone = PhoneNumber.normalizedE164(phone)
        guard normalizedName != nil || normalizedPhone != nil else {
            throw ValidationError.missingNameAndPhone
        }
    }

    public func age(on referenceDate: Date = .now, calendar: Calendar = .autoupdatingCurrent)
        -> Int?
    {
        guard let dob else {
            return nil
        }

        let years = calendar.dateComponents([.year], from: dob, to: referenceDate).year

        guard let years, years >= 0 else {
            return nil
        }

        return years
    }

    public var firstNameWithHonorific: String? {
        guard
            let name = name?.nilIfBlank,
            let firstName = name.split(whereSeparator: \.isWhitespace).first.map(String.init)
        else {
            return nil
        }

        if let honorific = gender?.honorific {
            return "\(honorific) \(firstName)"
        }
        return firstName
    }
}

public nonisolated enum Gender: Hashable, Sendable {
    case female
    case male
    case other

    public var displayName: String {
        switch self {
        case .female:
            "F"
        case .male:
            "M"
        case .other:
            "Other"
        }
    }

    public var honorific: String? {
        switch self {
        case .female:
            "Ms."
        case .male:
            "Mr."
        case .other:
            nil
        }
    }
}
