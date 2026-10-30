import ClinicalModels
import ClinicalPersistence
import Foundation
import SQLiteData

@MainActor @Observable
final class PaymentsModel {
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Fetch(PaymentDaysRequest(today: FinancialDate.today))
    var days: [PaymentDay] = []

    var error: (any Error)? { $days.loadError }

    func followClinicDays() async {
        while !Task.isCancelled {
            let date = now
            do {
                try await $days.load(PaymentDaysRequest(today: date))
            } catch {
                // Keep the day timer active after a read failure. The view shows loadError.
                if Task.isCancelled { return }
            }
            do {
                // Restart this wait on app activation. Suspension can cross clinic midnight.
                try await Task.sleep(
                    for: .seconds(max(0, FinancialDate.nextDay(date).timeIntervalSince(now))))
            } catch {
                return
            }
        }
    }
}
