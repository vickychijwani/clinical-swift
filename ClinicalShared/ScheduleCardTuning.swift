import SwiftUI

/// Defaults match the active-card surface. The app can override them for local design checks.
struct ScheduleCardTuning: Codable, Equatable, Sendable {
    var surfaceOpacity = 0.8
    var otherContentOpacity = 0.3
    var lift = Lift()

    struct Lift: Codable, Equatable, Sendable {
        var width = 0.02
        var shadowOpacity = 0.05
        var shadowRadius = 5.0
        var duration = 0.1
    }

    init() {}

    // Keep saved opacity values when the local tool gains new controls.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        surfaceOpacity = try values.decodeIfPresent(Double.self, forKey: .surfaceOpacity) ?? 0.8
        otherContentOpacity =
            try values.decodeIfPresent(Double.self, forKey: .otherContentOpacity) ?? 0.3
        lift = try values.decodeIfPresent(Lift.self, forKey: .lift) ?? Lift()
    }

    private enum CodingKeys: String, CodingKey {
        case surfaceOpacity, otherContentOpacity, lift
    }
}

extension EnvironmentValues {
    @Entry var scheduleCardTuning = ScheduleCardTuning()
}
