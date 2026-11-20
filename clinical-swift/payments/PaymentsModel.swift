import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

@MainActor @Observable
final class PaymentsModel {
    @ObservationIgnored @Fetch(PaymentDaysRequest(today: ClinicDate.today))
    var days: [PaymentDay] = []

    var filter: PaymentFilter = .all
    var filteredDays: [PaymentDay] { days.map { $0.filtered(by: filter) } }

    var error: (any Error)? { $days.loadError }

    func load(today: Date) async {
        do {
            try await $days.load(PaymentDaysRequest(today: today))
        } catch {
            // The view shows loadError.
        }
    }
}
