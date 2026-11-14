import XCTest

extension XCUIElement {
    @MainActor
    func frameSettledOrWait(timeout: TimeInterval) -> Bool {
        // A native sheet can report a hittable button before its animations end.
        // Sample across polls so an immediate first check cannot pass during motion.
        var previousFrame: CGRect?
        return waitUntil(timeout: timeout) {
            guard exists, isHittable else {
                previousFrame = nil
                return false
            }
            let frame = self.frame
            defer { previousFrame = frame }
            return previousFrame == frame
        }
    }

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
    func valueContainsOrWait(_ text: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            exists && (value as? String)?.contains(text) == true
        }
    }
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
