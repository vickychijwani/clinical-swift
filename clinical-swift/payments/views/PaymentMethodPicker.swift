import ClinicalModels
import SwiftUI

struct PaymentMethodPicker: View {
    @Binding var selection: AccountEntry.PaymentMethod?

    var body: some View {
        Picker("Payment method", selection: $selection) {
            Text("UPI").tag(AccountEntry.PaymentMethod.upi as AccountEntry.PaymentMethod?)
            Text("Cash").tag(AccountEntry.PaymentMethod.cash as AccountEntry.PaymentMethod?)
            Text("Card").tag(AccountEntry.PaymentMethod.card as AccountEntry.PaymentMethod?)
            Text("Other").tag(AccountEntry.PaymentMethod.other as AccountEntry.PaymentMethod?)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
