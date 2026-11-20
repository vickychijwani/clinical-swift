import Dependencies
import Foundation

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
        case otherIncome = "otherIncome"
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
            case .patientFees, .otherIncome:
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

    public enum ReceiptSource: Hashable, Sendable {
        case patient(UUID)
        case otherIncome

        public var category: Category {
            switch self {
            case .patient: .patientFees
            case .otherIncome: .otherIncome
            }
        }
    }

    public enum ExpenseCategory: String, CaseIterable, Sendable {
        case rent, staff, consultants, utilities, materials, repairsAndMaintenance
        case otherOperatingCosts, equipmentPurchases, clinicImprovements

        public var category: Category {
            switch self {
            case .rent: .rent
            case .staff: .staff
            case .consultants: .consultants
            case .utilities: .utilities
            case .materials: .materials
            case .repairsAndMaintenance: .repairsAndMaintenance
            case .otherOperatingCosts: .otherOperatingCosts
            case .equipmentPurchases: .equipmentPurchases
            case .clinicImprovements: .clinicImprovements
            }
        }
    }

    public enum Details: Hashable, Sendable {
        case charge(patientID: UUID, appointmentID: UUID?)
        case receipt(source: ReceiptSource, paymentMethod: PaymentMethod?)
        case expense(category: ExpenseCategory?, paymentMethod: PaymentMethod?)
        case adjustment(patientID: UUID)
    }

    public let id: UUID
    public var details: Details
    public var amount: Int
    public var entryDate: Date
    public let createdDate: Date
    public var note: String?

    public var kind: Kind {
        switch details {
        case .charge: .charge
        case .receipt: .receipt
        case .expense: .expense
        case .adjustment: .adjustment
        }
    }

    public var patientID: UUID? {
        switch details {
        case .charge(let id, _), .adjustment(let id), .receipt(.patient(let id), _): id
        case .receipt, .expense: nil
        }
    }

    public var appointmentID: UUID? {
        if case .charge(_, let id) = details { id } else { nil }
    }

    public var category: Category? {
        switch details {
        case .receipt(let source, _): source.category
        case .expense(let category, _): category?.category
        case .charge, .adjustment: nil
        }
    }

    public var paymentMethod: PaymentMethod? {
        switch details {
        case .receipt(_, let method), .expense(_, let method): method
        case .charge, .adjustment: nil
        }
    }

    public init(
        id: UUID = UUID(), details: Details, amount: Int, entryDate: Date? = nil,
        createdDate: Date? = nil, note: String? = nil
    ) {
        @Dependency(\.date.now) var now
        self.id = id
        self.details = details
        self.amount = amount
        self.entryDate = ClinicDate.day(entryDate ?? now)
        self.createdDate = createdDate ?? now
        self.note = note?.nilIfBlank
    }

    /// Reports validate values without a dependency on today's date.
    public func validateValues() throws {
        guard amount != 0, amount != Int.min, kind == .adjustment || amount > 0 else {
            throw AccountEntryError.invalidAmount
        }
        guard entryDate.timeIntervalSinceReferenceDate.isFinite,
            createdDate.timeIntervalSinceReferenceDate.isFinite
        else { throw AccountEntryError.invalidFields }
    }

    public func validate() throws {
        try validateValues()
        guard ClinicDate.day(entryDate) <= ClinicDate.today else {
            throw AccountEntryError.futureDate
        }
    }

    public var balanceChange: Int {
        get throws {
            try validateValues()
            switch details {
            case .charge, .adjustment: return amount
            case .receipt(.patient, _): return -amount
            case .receipt, .expense: return 0
            }
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
