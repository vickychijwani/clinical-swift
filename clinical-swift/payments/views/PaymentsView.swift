import ClinicalModels
import SwiftUI

struct PaymentsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = PaymentsModel()

    var body: some View {
        List {
            if model.error != nil {
                Text("Payments could not be loaded.")
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(model.days) { day in
                    Section {
                        if day.items.isEmpty {
                            Text("No payments")
                                .foregroundStyle(AppColor.secondaryText)
                                .paymentRowInsets()
                        } else {
                            ForEach(day.items) { item in
                                PaymentRow(item: item)
                                    .paymentRowInsets()
                            }
                        }
                    } header: {
                        PaymentDayHeader(day: day)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppColor.canvas)
        .navigationTitle("Payments")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(AppColor.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .colorLabOverlay(isVisible: true)
        .task(id: scenePhase) {
            if scenePhase == .active { await model.followClinicDays() }
        }
    }
}

struct PaymentRow: View {
    let item: PaymentItem

    var body: some View {
        HStack {
            Image(systemName: item.isReceipt ? "arrow.down.right" : "arrow.up.right")
                .font(.headline.pointSize(13))
                .foregroundStyle(item.isReceipt ? AppColor.receipt : .expense)
                .frame(width: 34, height: 34)
                .background(item.isReceipt ? AppColor.receiptBackground : .expenseBackground)
                .clipShape(.circle)
            VStack(alignment: .leading) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                if let method = item.method {
                    Text(method)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Text(item.amount)
                .bold()
                .foregroundStyle(item.isReceipt ? AppColor.receipt : .expense)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct PaymentDayHeader: View {
    let day: PaymentDay

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(day.title)
                Spacer()
                PaymentDayTotals(day: day)
            }
            VStack(alignment: .leading) {
                Text(day.title)
                PaymentDayTotals(day: day)
            }
        }
        .foregroundStyle(AppColor.secondaryText)
        .textCase(nil)
    }
}

private struct PaymentDayTotals: View {
    let day: PaymentDay

    var body: some View {
        HStack {
            if let receipts = day.receipts {
                Text(PaymentItem.amount(receipts, isReceipt: true))
                    .foregroundStyle(AppColor.receipt)
            }
            if day.receipts != nil && day.expenses != nil { Text("·") }
            if let expenses = day.expenses {
                Text(PaymentItem.amount(expenses, isReceipt: false))
                    .foregroundStyle(AppColor.expense)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

extension View {
    fileprivate func paymentRowInsets() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            // Use the same full-row separator anchors as the Patients list.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 6 }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] - 6 }
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .listRowBackground(Rectangle().fill(AppColor.surface))
    }
}
