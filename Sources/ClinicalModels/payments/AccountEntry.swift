import Dependencies
import Foundation

/// Financial days follow the clinic, even when the device uses another calendar or time zone.
public nonisolated enum FinancialDate {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // This identifier is part of Foundation's time zone database.
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }

    public static var today: Date {
        @Dependency(\.date.now) var now
        return day(now)
    }

    public static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public static func nextDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day(date))!
    }
}

public nonisolated struct AccountEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case charge = "charge"
        case receipt = "receipt"
        case expense = "expense"
        case adjustment = "adjustment"
    }

    public enum ReportingGroup: String, CaseIterable, Sendable {
        case incoming, operating, capital
    }

    public enum Category: String, CaseIterable, Sendable {
        case patientFees = "patientFees"
        case externalConsultations = "externalConsultations"
        case referralCommissions = "referralCommissions"
        case otherReceipts = "otherReceipts"
        case rent = "rent"
        case staff = "staff"
        case consultants = "consultants"
        case utilities = "utilities"
        case materials = "materials"
        case repairsAndMaintenance = "repairsAndMaintenance"
        case otherOperatingCosts = "otherOperatingCosts"
        case equipmentPurchases = "equipmentPurchases"
        case clinicImprovements = "clinicImprovements"

        public var group: ReportingGroup {
            switch self {
            case .patientFees, .externalConsultations, .referralCommissions, .otherReceipts:
                .incoming
            case .equipmentPurchases, .clinicImprovements: .capital
            case .rent, .staff, .consultants, .utilities, .materials, .repairsAndMaintenance,
                .otherOperatingCosts:
                .operating
            }
        }
    }

    public enum PaymentMethod: String, CaseIterable, Sendable {
        case cash = "cash"
        case upi = "upi"
        case card = "card"
        case other = "other"
    }

    public let id: UUID
    public var kind: Kind
    public var amount: Int
    public var entryDate: Date
    public let createdDate: Date
    public var patientID: UUID?
    public var appointmentID: UUID?
    public var category: Category?
    public var note: String?
    public var paymentMethod: PaymentMethod?

    public init(
        id: UUID = UUID(), kind: Kind, amount: Int, entryDate: Date? = nil,
        createdDate: Date? = nil, patientID: UUID? = nil, appointmentID: UUID? = nil,
        category: Category? = nil, note: String? = nil, paymentMethod: PaymentMethod? = nil
    ) {
        @Dependency(\.date.now) var now
        self.id = id
        self.kind = kind
        self.amount = amount
        self.entryDate = FinancialDate.day(entryDate ?? now)
        self.createdDate = createdDate ?? now
        self.patientID = patientID
        self.appointmentID = appointmentID
        self.category = category
        self.note = note?.nilIfBlank
        self.paymentMethod = paymentMethod
    }

    public func validate() throws {
        guard amount != 0, amount != Int.min, kind == .adjustment || amount > 0 else {
            throw AccountEntryError.invalidAmount
        }
        guard entryDate.timeIntervalSinceReferenceDate.isFinite,
            FinancialDate.day(entryDate) <= FinancialDate.today
        else { throw AccountEntryError.futureDate }
        let valid: Bool
        switch kind {
        case .charge:
            valid = patientID != nil && category == nil && paymentMethod == nil
        case .adjustment:
            valid =
                patientID != nil && appointmentID == nil && category == nil && paymentMethod == nil
        case .receipt:
            valid =
                category?.group == .incoming && appointmentID == nil
                && ((category == .patientFees) == (patientID != nil))
        case .expense:
            valid =
                patientID == nil && appointmentID == nil && category != nil
                && category?.group != .incoming
        }
        guard valid else { throw AccountEntryError.invalidFields }
    }

    public var balanceChange: Int {
        get throws {
            guard amount != Int.min else { throw AccountEntryError.invalidAmount }
            guard patientID != nil else { return 0 }
            return kind == .receipt ? -amount : amount
        }
    }
}

public nonisolated enum AccountEntryError: Error, Equatable, Sendable {
    case invalidAmount, invalidFields, futureDate, overflow
    case invalidStoredValue(String)
    case missingEntry(UUID)
    case missingPatient(UUID)
    case missingAppointment(UUID)
    case duplicateMutation(UUID)
    case appointmentPatientMismatch, appointmentHasCharges
    case negativeBalance(UUID)
    case negativeTargetBalance
}

/// Use checked arithmetic for financial totals, including reports that do not write data.
public nonisolated func addingMoney(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw AccountEntryError.overflow }
    return result
}
