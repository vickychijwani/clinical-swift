import XCTest

extension XCUIElement {
    @MainActor
    func existsOrWait(timeout: TimeInterval) -> Bool {
        // XCTest can delay its first poll even when the element is already present.
        exists || waitForExistence(timeout: timeout)
    }

    @MainActor
    func hittableOrWait(timeout: TimeInterval) -> Bool {
        isHittable || wait(for: \.isHittable, toEqual: true, timeout: timeout)
    }

    @MainActor
    func valueContainsOrWait(_ text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND value CONTAINS %@", text)
        return predicate.evaluate(with: self)
            || XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: self)],
                timeout: timeout
            ) == .completed
    }
}
