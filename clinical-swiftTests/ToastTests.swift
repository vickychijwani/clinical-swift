import Dependencies
import Foundation
import Synchronization
import Testing

@testable import clinical_swift

@MainActor
struct ToastTests {
    @Test func autoDismissesAfterConfiguredDuration() async {
        let clock = ManualClock()
        let store = withDependencies {
            $0.continuousClock = clock
        } operation: {
            ToastStore()
        }

        store.show(message: "Appointment completed", actionTitle: "View") {}
        #expect(store.current?.message == "Appointment completed")

        await clock.waitForSleeper(count: 1)
        await clock.advance(by: .seconds(3))
        #expect(store.current != nil)

        await clock.advance(by: .seconds(1))
        #expect(store.current == nil)
    }

    @Test func replacingToastCancelsPriorAutoDismissTimer() async {
        let clock = ManualClock()
        let store = withDependencies {
            $0.continuousClock = clock
        } operation: {
            ToastStore()
        }

        store.show(message: "First", duration: .seconds(4))
        await clock.waitForSleeper(count: 1)
        await clock.advance(by: .seconds(2))

        store.show(message: "Second", duration: .seconds(4))
        await clock.waitForSleeper(count: 2)
        await clock.advance(by: .seconds(2))
        #expect(store.current?.message == "Second")

        await clock.advance(by: .seconds(2))
        #expect(store.current == nil)
    }

    @Test func staleIDGuardsIgnoreOutdatedDismissAndActionCalls() async {
        let clock = ManualClock()
        let store = withDependencies {
            $0.continuousClock = clock
        } operation: {
            ToastStore()
        }

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
        let clock = ManualClock()
        let store = withDependencies {
            $0.continuousClock = clock
        } operation: {
            ToastStore()
        }

        store.show(message: "Reminder saved", duration: nil)
        await clock.advance(by: .seconds(60))
        #expect(store.current?.message == "Reminder saved")

        store.dismiss()
        #expect(store.current == nil)
    }
}

private final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepCount = 0
        var sleepers:
            [(id: UUID, deadline: Instant, continuation: CheckedContinuation<Void, any Error>)] = []
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Decision {
                    case immediate
                    case cancelled
                    case pending
                }
                let decision = state.withLock { state -> Decision in
                    state.sleepCount += 1
                    if Task.isCancelled {
                        return .cancelled
                    }
                    if deadline <= state.now {
                        return .immediate
                    }
                    state.sleepers.append((id, deadline, continuation))
                    return .pending
                }
                switch decision {
                case .immediate:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .pending:
                    break
                }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    return nil
                }
                return state.sleepers.remove(at: index).continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func waitForSleeper(count: Int) async {
        while state.withLock({ $0.sleepCount < count }) {
            await Task.yield()
        }
    }

    func advance(by duration: Duration) async {
        let ready = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
            state.now = state.now.advanced(by: duration)
            var due: [CheckedContinuation<Void, any Error>] = []
            state.sleepers.removeAll { sleeper in
                if sleeper.deadline <= state.now {
                    due.append(sleeper.continuation)
                    return true
                }
                return false
            }
            return due
        }
        for continuation in ready {
            continuation.resume()
        }
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
