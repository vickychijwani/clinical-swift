import CoreGraphics
import Foundation
import Testing

@testable import clinical_swift

#if DEBUG
    @MainActor
    struct TimelineTuningTests {
        @Test func restoresValuesAndPanelState() throws {
            let suite = "TimelineTuningTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let tuning = TimelineTuning(defaults: defaults)
            tuning.state.isEnabled = true
            tuning.state.isExpanded = false
            tuning.state.position = .init(x: 0.25, y: 0.6)
            tuning.state.cards.surfaceOpacity = 0.8
            tuning.state.cards.otherContentOpacity = 0.2
            tuning.state.cards.lift.width = 0.012
            tuning.state.cards.lift.shadowOpacity = 0.2
            tuning.state.cards.lift.shadowRadius = 12
            tuning.state.cards.lift.duration = 0.2

            #expect(TimelineTuning(defaults: defaults).state == tuning.state)

            tuning.reset()
            #expect(tuning.state.cards == ScheduleCardTuning())
            #expect(tuning.state.isEnabled)
            #expect(!tuning.state.isExpanded)
            #expect(tuning.state.position == .init(x: 0.25, y: 0.6))
            #expect(TimelineTuning(defaults: defaults).state == tuning.state)
        }

        @Test func oldCardLabValuesKeepOpacityAndGainLiftDefaults() throws {
            let data = Data(
                #"{"surfaceOpacity":0.73,"otherContentOpacity":0.21,"glass":"Regular","material":"Thick","materialOpacity":0.4,"isInteractive":false}"#
                    .utf8)
            let cards = try JSONDecoder().decode(ScheduleCardTuning.self, from: data)
            #expect(cards.surfaceOpacity == 0.73)
            #expect(cards.otherContentOpacity == 0.21)
            #expect(cards.lift == ScheduleCardTuning.Lift())
        }

        @Test func approvedValuesReplaceEarlierTuningOnceWithoutMovingPanel() throws {
            let suite = "TimelineTuningTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var saved = TimelineTuning.SavedState()
            saved.isEnabled = true
            saved.isExpanded = false
            saved.position = .init(x: 0.25, y: 0.6)
            saved.cards.surfaceOpacity = 0.55
            saved.cards.otherContentOpacity = 0.35
            defaults.set(
                try JSONEncoder().encode(saved), forKey: "developer.timelineTuning.v1")

            let tuning = TimelineTuning(defaults: defaults)
            #expect(tuning.state.cards == ScheduleCardTuning())
            #expect(tuning.state.isEnabled)
            #expect(!tuning.state.isExpanded)
            #expect(tuning.state.position == saved.position)

            tuning.state.cards.surfaceOpacity = 0.77
            #expect(TimelineTuning(defaults: defaults).state == tuning.state)
        }

        @Test func headerDragCanPlacePanelBetweenCorners() {
            let space = CGSize(width: 400, height: 800)
            let panel = CGSize(width: 200, height: 400)
            var position = TimelineTuning.Position(x: 0, y: 0)
            position.move(by: CGSize(width: 73, height: 129), in: space, panel: panel)
            #expect(position.origin(in: space, panel: panel) == CGPoint(x: 81, y: 137))

            position.move(by: CGSize(width: -20, height: 17), in: space, panel: panel)
            #expect(position.origin(in: space, panel: panel) == CGPoint(x: 61, y: 154))
        }

        @Test func dragClampsAtEveryEdge() {
            let space = CGSize(width: 400, height: 800)
            let panel = CGSize(width: 200, height: 400)
            var position = TimelineTuning.Position()
            let farOutside = CGSize(width: 10_000, height: 10_000)
            #expect(
                position.origin(in: space, panel: panel, translation: farOutside)
                    == CGPoint(x: 192, y: 392))
            position.move(by: farOutside, in: space, panel: panel)
            #expect(position.origin(in: space, panel: panel) == CGPoint(x: 192, y: 392))
            position.move(by: CGSize(width: -10_000, height: -10_000), in: space, panel: panel)
            #expect(position == .init(x: 0, y: 0))
        }

        @Test func positionFitsAfterExpansionAndOnSmallerSheet() {
            let position = TimelineTuning.Position(x: 0.25, y: 0.25)
            #expect(
                position.origin(
                    in: CGSize(width: 400, height: 800), panel: CGSize(width: 200, height: 40))
                    == CGPoint(x: 108, y: 208))
            #expect(
                position.origin(
                    in: CGSize(width: 320, height: 500), panel: CGSize(width: 288, height: 400))
                    == CGPoint(x: 24, y: 92))
        }

        @Test func collapseKeepsPlacedHeaderStill() {
            let space = CGSize(width: 400, height: 800)
            var position = TimelineTuning.Position(x: 0, y: 0)
            position.move(
                by: CGSize(width: 70, height: 100), in: space,
                panel: CGSize(width: 288, height: 420))
            #expect(
                position.origin(in: space, panel: CGSize(width: 288, height: 420))
                    == position.origin(in: space, panel: CGSize(width: 188, height: 52)))
        }

        @Test func noFreeSpaceDoesNotLoseSavedPosition() {
            var position = TimelineTuning.Position(x: 0.4, y: 0.7)
            position.move(by: CGSize(width: 100, height: 100), in: .zero, panel: .zero)
            #expect(position == .init(x: 0.4, y: 0.7))
            #expect(position.origin(in: .zero, panel: .zero) == CGPoint(x: 8, y: 8))
        }
    }
#endif
