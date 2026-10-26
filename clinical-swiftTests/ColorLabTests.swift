import Foundation
import SwiftUI
import Testing

@testable import clinical_swift

#if DEBUG
    @MainActor
    struct ColorLabTests {
        @Test func restoresColorsAndPanelStateWithoutChangingCardLab() throws {
            let suite = "ColorLabTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let cards = TimelineTuning(defaults: defaults)
            cards.state.cards.surfaceOpacity = 0.42
            let lab = ColorLab(defaults: defaults)
            lab.state.isEnabled = true
            lab.state.isExpanded = false
            lab.state.position = .init(x: 0.2, y: 0.4)
            lab.state.selected = .card
            lab.state.colors[.card] = .custom(.init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
            lab.state.colors[.text] = .system(.indigo)
            #expect(ColorLab(defaults: defaults).state == lab.state)
            #expect(lab.palette[.text] == .indigo)

            lab.state.isEnabled = false
            #expect(lab.state.colors.count == 2)
            lab.state.colors[.card] = nil
            #expect(lab.palette[.card] == AppPalette()[.card])
            #expect(lab.state.colors[.text] == .system(.indigo))
            lab.reset()
            #expect(lab.state.colors.isEmpty)
            #expect(!lab.state.isExpanded)
            #expect(lab.state.position == .init(x: 0.2, y: 0.4))
            #expect(ColorLab(defaults: defaults).state == lab.state)
            #expect(TimelineTuning(defaults: defaults).state == cards.state)
        }

        @Test func damagedPreferencesUseDefaults() throws {
            let suite = "ColorLabTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(Data("broken".utf8), forKey: "developer.colorLab.v1")
            #expect(ColorLab(defaults: defaults).state == ColorLab.SavedState())
        }

        @Test func todaySelectionPersistsWhenHiddenAndResetsWithColors() throws {
            let suite = "ColorLabTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let lab = ColorLab(defaults: defaults)
            #expect(lab.palette.todaySelection.textColor == .white)
            #expect(lab.palette.todaySelection.highlightOpacity == 1)
            lab.state.todaySelection = .init(usesWhiteText: false, highlightOpacity: 0.35)
            lab.state.isEnabled = false
            let restored = ColorLab(defaults: defaults)
            #expect(restored.palette.todaySelection.textColor == .black)
            #expect(restored.palette.todaySelection.highlightOpacity == 0.35)
            restored.state.colors[.accent] = .system(.purple)
            restored.reset()
            #expect(restored.palette == AppPalette())
            #expect(ColorLab(defaults: defaults).palette == AppPalette())
        }

        @Test func savedColorsWithoutTodaySelectionKeepTheirValues() throws {
            let suite = "ColorLabTests.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var state = ColorLab.SavedState()
            state.isEnabled = true
            state.colors[.accent] = .system(.purple)
            // A nil optional is omitted, as in preferences saved before the today controls existed.
            defaults.set(try JSONEncoder().encode(state), forKey: "developer.colorLab.v1")
            let restored = ColorLab(defaults: defaults)
            #expect(restored.state.isEnabled)
            #expect(restored.palette[.accent] == .purple)
            #expect(restored.palette.todaySelection == .init())
        }

        @Test func hslRoundTripPreservesChannelsAndOpacity() {
            for red in [0.0, 0.2, 0.7, 1.0] {
                for green in [0.0, 0.3, 0.8, 1.0] {
                    for blue in [0.0, 0.4, 0.9, 1.0] {
                        let source = ColorLab.RGBA(red: red, green: green, blue: blue, alpha: 0.37)
                        let result = ColorLab.RGBA(hsl: source.hsl, alpha: source.alpha)
                        #expect(abs(result.red - red) < 0.000001)
                        #expect(abs(result.green - green) < 0.000001)
                        #expect(abs(result.blue - blue) < 0.000001)
                        #expect(result.alpha == source.alpha)
                    }
                }
            }
        }

        @Test func hexAcceptsRGBAndPreservesSeparateOpacity() throws {
            let expected = ColorLab.RGBA(
                red: 18.0 / 255, green: 171.0 / 255, blue: 239.0 / 255, alpha: 0.37)
            #expect(ColorLab.RGBA(hex: "#12AbEf", alpha: 0.37) == expected)
            #expect(ColorLab.RGBA(hex: " 12ABEF ", alpha: 0.37) == expected)
            #expect(expected.hex == "#12ABEF")
            #expect(ColorLab.RGBA(red: 0, green: 0, blue: 0).hex == "#000000")
            #expect(ColorLab.RGBA(red: 1, green: 1, blue: 1).hex == "#FFFFFF")
            let translucent = try #require(ColorLab.RGBA(hex: "#123456", alpha: 0.2))
            #expect(translucent.alpha == 0.2)
            #expect(ColorLab.RGBA(hex: translucent.hex, alpha: 0.8)?.alpha == 0.8)
            for invalid in ["", "#123", "#12345", "#12345678", "#GG0000", "+12345", "＃123456"] {
                #expect(ColorLab.RGBA(hex: invalid, alpha: 1) == nil)
            }
        }

        @Test func hslKnownColorsAndHueWrap() {
            #expect(
                ColorLab.RGBA(red: 1, green: 0, blue: 0).hsl
                    == .init(hue: 0, saturation: 1, lightness: 0.5))
            #expect(ColorLab.RGBA(red: 0, green: 1, blue: 0).hsl.hue == 120)
            #expect(ColorLab.RGBA(red: 0, green: 0, blue: 1).hsl.hue == 240)
            #expect(
                ColorLab.RGBA(red: 0.5, green: 0.5, blue: 0.5).hsl
                    == .init(hue: 0, saturation: 0, lightness: 0.5))
            #expect(
                ColorLab.RGBA(hsl: .init(hue: 360, saturation: 1, lightness: 0.5), alpha: 1)
                    == .init(red: 1, green: 0, blue: 0))
        }

        @Test func defaultAccentRolesFollowAccentUntilOverridden() {
            var palette = AppPalette()
            palette.overrides[.accent] = .purple
            #expect(palette[.draftCard] == Color.purple.opacity(0.08))
            #expect(palette[.activeBorder] == Color.purple.opacity(0.7))
            palette.overrides[.activeBorder] = .blue
            #expect(palette[.activeBorder] == .blue)
            palette.overrides[.accent] = .green
            #expect(palette[.activeBorder] == .blue)
            #expect(palette[.draftBorder] == Color.green.opacity(0.5))
        }
    }
#endif
