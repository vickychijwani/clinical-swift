import SwiftUI

/// Defaults match the draft card surface. The app can override them for local design checks.
/// Also stores overlapping schedule layout tuning.
nonisolated struct ScheduleCardTuning: Codable, Equatable, Sendable {
    var surfaceOpacity = 0.8
    var otherContentOpacity = 0.3
    var lift = Lift()
    var overlap = Overlap()

    nonisolated struct Lift: Codable, Equatable, Sendable {
        var width = 0.02
        var shadowOpacity = 0.05
        var shadowRadius = 5.0
        var duration = 0.1
    }

    nonisolated struct Overlap: Codable, Equatable, Sendable {
        enum Mode: String, CaseIterable, Codable, Identifiable, Sendable {
            case current = "Current"
            case cascade = "Cascade"
            case textAware = "Text-aware"

            var id: Self { self }
        }

        enum Separation: String, CaseIterable, Codable, Identifiable, Sendable {
            case shadow = "Shadow"
            case flat = "Flat"

            var id: Self { self }
        }

        var mode: Mode = .textAware
        var separation: Separation = .shadow
        /// Minimum continuous left strip left uncovered on every overlapped back card.
        var stripWidth = 16.0
        var shadowOpacity = 0.09
        var shadowRadius = 2.0

        static let widget = Overlap(
            mode: .textAware,
            separation: .shadow,
            stripWidth: 12.0,
            shadowOpacity: 0.09,
            shadowRadius: 1.5
        )
    }
}

extension EnvironmentValues {
    @Entry var scheduleCardTuning = ScheduleCardTuning()
}
