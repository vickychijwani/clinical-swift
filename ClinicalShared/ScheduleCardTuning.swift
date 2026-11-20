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

        init(
            mode: Mode = .textAware,
            separation: Separation = .shadow,
            stripWidth: Double = 16.0,
            shadowOpacity: Double = 0.09,
            shadowRadius: Double = 2.0
        ) {
            self.mode = mode
            self.separation = separation
            self.stripWidth = stripWidth
            self.shadowOpacity = shadowOpacity
            self.shadowRadius = shadowRadius
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .textAware
            // Fall back to `.shadow` if saved preferences still contain removed separation styles.
            let rawSeparation = try values.decodeIfPresent(String.self, forKey: .separation)
            separation = rawSeparation.flatMap(Separation.init(rawValue:)) ?? .shadow
            stripWidth = try values.decodeIfPresent(Double.self, forKey: .stripWidth) ?? 16.0
            shadowOpacity = try values.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.09
            shadowRadius = try values.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 2.0
        }

        private enum CodingKeys: String, CodingKey {
            case mode, separation, stripWidth, shadowOpacity, shadowRadius
        }
    }

    init() {}

    // Keep saved opacity values when the local tool gains new controls.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        surfaceOpacity = try values.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 0.8
        otherContentOpacity =
            try values.decodeIfPresent(Double.self, forKey: .otherContentOpacity) ?? 0.3
        lift = try values.decodeIfPresent(Lift.self, forKey: .lift) ?? Lift()
        overlap = try values.decodeIfPresent(Overlap.self, forKey: .overlap) ?? Overlap()
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceOpacity, otherContentOpacity, lift, overlap
    }
}

extension EnvironmentValues {
    @Entry var scheduleCardTuning = ScheduleCardTuning()
}
