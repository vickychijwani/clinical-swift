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
            case halo = "Halo"
            case shadow = "Shadow"
            case flat = "Flat"

            var id: Self { self }
        }

        var mode: Mode = .textAware
        var separation: Separation = .halo
        /// Minimum continuous left strip left uncovered on every overlapped back card.
        var stripWidth = 18.0
        /// Outer canvas-colored outline around overlapping front cards in `.halo` mode.
        var haloWidth = 2.0
        var shadowOpacity = 0.12
        var shadowRadius = 6.0

        init(
            mode: Mode = .textAware,
            separation: Separation = .halo,
            stripWidth: Double = 18.0,
            haloWidth: Double = 2.0,
            shadowOpacity: Double = 0.12,
            shadowRadius: Double = 6.0
        ) {
            self.mode = mode
            self.separation = separation
            self.stripWidth = stripWidth
            self.haloWidth = haloWidth
            self.shadowOpacity = shadowOpacity
            self.shadowRadius = shadowRadius
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .textAware
            separation = try values.decodeIfPresent(Separation.self, forKey: .separation) ?? .halo
            stripWidth = try values.decodeIfPresent(Double.self, forKey: .stripWidth) ?? 18.0
            haloWidth = try values.decodeIfPresent(Double.self, forKey: .haloWidth) ?? 2.0
            shadowOpacity = try values.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.12
            shadowRadius = try values.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 6.0
        }

        private enum CodingKeys: String, CodingKey {
            case mode, separation, stripWidth, haloWidth, shadowOpacity, shadowRadius
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
