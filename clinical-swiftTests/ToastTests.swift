import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct ToastTests {
    @Test func autoDismissesAfterConfiguredDuration() async {
        let (store, clock) = makeStore()

        store.show(message: "Appointment completed", actionTitle: "View") {}
        #expect(store.current?.message == "Appointment completed")

        await clock.advance(by: .seconds(3))
        #expect(store.current != nil)

        await clock.advance(by: .seconds(1))
        #expect(store.current == nil)
    }

    @Test func replacingToastCancelsPriorAutoDismissTimer() async {
        let (store, clock) = makeStore()

        store.show(message: "First", duration: .seconds(4))
        await clock.advance(by: .seconds(2))

        store.show(message: "Second", duration: .seconds(4))
        await clock.advance(by: .seconds(2))
        #expect(store.current?.message == "Second")

        await clock.advance(by: .seconds(2))
        #expect(store.current == nil)
    }

    @Test func staleIDGuardsIgnoreOutdatedDismissAndActionCalls() async {
        let (store, _) = makeStore()

        var firstCalls = 0
        let first = ToastItem(message: "First", actionTitle: "Undo", duration: nil) {
            firstCalls += 1
        }
        store.show(first)

        var secondCalls = 0
        let second = ToastItem(message: "Second", actionTitle: "View", duration: nil) {
            secondCalls += 1
        }
        store.show(second)

        store.dismiss(id: first.id)
        store.triggerAction(for: first.id)
        #expect(store.current?.id == second.id)
        #expect(firstCalls == 0)

        store.triggerAction(for: second.id)
        #expect(store.current == nil)
        #expect(secondCalls == 1)
    }

    @Test func nilDurationRemainsVisibleUntilExplicitDismiss() async {
        let (store, clock) = makeStore()

        store.show(message: "Reminder saved", duration: nil)
        await clock.advance(by: .seconds(60))
        #expect(store.current?.message == "Reminder saved")

        store.dismiss()
        #expect(store.current == nil)
    }

    @Test func actionPreservesOptionalSystemImage() {
        let (store, _) = makeStore()

        store.show(
            message: "Appointment booked",
            actionTitle: "Message",
            actionSystemImage: "arrow.up.message",
            duration: nil
        ) {}
        #expect(store.current?.action?.title == "Message")
        #expect(store.current?.action?.systemImage == "arrow.up.message")

        store.show(message: "Completed", actionTitle: "Book follow-up", duration: nil) {}
        #expect(store.current?.action?.title == "Book follow-up")
        #expect(store.current?.action?.systemImage == nil)
    }

    private func makeStore() -> (store: ToastStore, clock: TestClock<Duration>) {
        let clock = TestClock()
        let store = withDependencies {
            $0.continuousClock = clock
        } operation: {
            ToastStore()
        }
        return (store, clock)
    }
}
