import ClinicalModels
import Dependencies
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var clinicToday: Date = ClinicDate.today
}

/// Follows clinic-day boundaries in Asia/Kolkata and notifies the caller when the day changes.
@MainActor
func followClinicDays(
    initialDay: Date? = nil,
    onDayChange: @MainActor (Date) -> Void
) async {
    @Dependency(\.date) var date
    @Dependency(\.continuousClock) var clock

    var currentDay = initialDay
    while !Task.isCancelled {
        let now = date.now
        let today = ClinicDate.day(now)
        if currentDay != today {
            currentDay = today
            onDayChange(today)
        }

        let nextMidnight = ClinicDate.nextDay(today)
        let remaining = nextMidnight.timeIntervalSince(now)
        guard remaining > 0 else { return }

        do {
            try await clock.sleep(for: .seconds(remaining))
        } catch {
            return
        }

        // Stop if the injected date did not move forward, so tests cannot busy-spin.
        if date.now <= now {
            return
        }
    }
}

/// Publishes the active clinic day in the SwiftUI environment and refreshes it across midnight,
/// app activation, and system time changes.
struct ClinicDayModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = ClinicDate.today
    @State private var clockChangeCount = 0

    func body(content: Content) -> some View {
        content
            .environment(\.clinicToday, today)
            // Restart this wait on app activation. Suspension can cross clinic midnight.
            .task(id: RolloverTrigger(isActive: scenePhase == .active, clockChangeCount: clockChangeCount)) {
                guard scenePhase == .active else { return }
                await followClinicDays(initialDay: today) { next in
                    if next != today {
                        today = next
                    }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)
            ) { _ in
                let next = ClinicDate.today
                if next != today {
                    today = next
                }
                // Restart the rollover sleep when manual clock or NTP jumps change the wait duration.
                clockChangeCount += 1
            }
    }
}

private struct RolloverTrigger: Equatable {
    let isActive: Bool
    let clockChangeCount: Int
}
