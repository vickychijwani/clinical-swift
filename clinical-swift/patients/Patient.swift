import Foundation

nonisolated struct Patient: Identifiable, Hashable, Sendable {
    static let unknownDisplayName = "Unknown Patient"

    let id: UUID
    let name: String?
    let phone: String?
    let dob: Date?
    let gender: Gender?
    let createdDate: Date

    enum ValidationError: Error, Equatable {
        case missingNameAndPhone
    }

    init(
        id: UUID = UUID(),
        name: String?,
        phone: String? = nil,
        dob: Date? = nil,
        gender: Gender? = nil,
        createdDate: Date = .now
    ) {
        let normalizedName = name?.nilIfBlank
        let normalizedPhone = phone?.nilIfBlank

        self.id = id
        self.name = normalizedName
        self.phone = normalizedPhone
        self.dob = dob
        self.gender = gender
        self.createdDate = createdDate
    }

    var displayName: String {
        name ?? Self.unknownDisplayName
    }

    var isUnknown: Bool {
        name == nil
    }

    func validate() throws {
        let normalizedName = name?.nilIfBlank
        let normalizedPhone = phone?.nilIfBlank
        guard normalizedName != nil || normalizedPhone != nil else {
            throw ValidationError.missingNameAndPhone
        }
    }

    func age(on referenceDate: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        guard let dob else {
            return nil
        }

        let years = calendar.dateComponents([.year], from: dob, to: referenceDate).year

        guard let years, years >= 0 else {
            return nil
        }

        return years
    }
}
