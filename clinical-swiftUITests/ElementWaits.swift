import XCTest

extension XCUIElement {
    @MainActor
    func existsOrWait(timeout: TimeInterval) -> Bool {
        // Poll frequently instead of XCTest's ~1-second retry interval.
        waitUntil(timeout: timeout) { exists }
    }

    @MainActor
    func absentOrWait(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { !exists }
    }

    @MainActor
    func hittableOrWait(timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { isHittable }
    }

    @MainActor
    func stableFrameOrWait(timeout: TimeInterval) -> Bool {
        var previous: CGRect?
        var unchangedSince = ContinuousClock.now
        return waitUntil(timeout: timeout) {
            guard exists, isHittable else {
                previous = nil
                unchangedSince = .now
                return false
            }
            let current = frame
            if current != previous {
                previous = current
                unchangedSince = .now
                return false
            }
            // Custom trays use SwiftUI motion, which the UIKit switch does not disable.
            return unchangedSince.duration(to: .now) >= .milliseconds(150)
        }
    }

    @MainActor
    func valueContainsOrWait(_ text: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            exists && (value as? String)?.contains(text) == true
        }
    }
}

@MainActor
func measureUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.025,
    condition: () -> Bool
) -> Duration? {
    let start = ContinuousClock.now
    if condition() { return start.duration(to: .now) }
    let deadline = start + .seconds(timeout)
    while ContinuousClock.now < deadline {
        RunLoop.current.run(until: Date.now.addingTimeInterval(pollInterval))
        if condition() { return start.duration(to: .now) }
    }
    return nil
}

@MainActor
private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    if condition() { return true }
    let deadline = ContinuousClock.now + .seconds(timeout)
    while ContinuousClock.now < deadline {
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        if condition() { return true }
    }
    return false
}
