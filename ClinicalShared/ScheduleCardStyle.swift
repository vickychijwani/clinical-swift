import CoreGraphics
import CoreText
import Foundation

nonisolated enum ScheduleCardStyle {
    static let cornerRadius: CGFloat = 8
    static let horizontalPadding: CGFloat = 8
    static let stackedTopSpacerHeight: CGFloat = 4
    static let stackedSpacing: CGFloat = 2
    static let compactStackedSpacing: CGFloat = 0
    static let compactHorizontalSpacing: CGFloat = 8
    static let timeIconSpacing: CGFloat = 2
    static let timeFontSize: CGFloat = 12
    static let timeTracking: CGFloat = 0.4
    static let labelFontSize: CGFloat = 14
    static let compactTimeFontSize: CGFloat = 10
    static let compactLabelFontSize: CGFloat = 12

    static func formattedTime(_ date: Date, compact: Bool) -> String {
        if compact {
            return date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        }
        return date.formatted(.dateTime.hour().minute())
    }
}

/// Conservative content bounds shared by ScheduleCard and TimelineLayoutEngine.
/// Uses CoreText so the layout engine stays independent of SwiftUI.
nonisolated struct ScheduleCardContentMetrics: Sendable {
    struct Bounds: Equatable, Sendable {
        let width: CGFloat
        let height: CGFloat
        let isStacked: Bool
    }

    // Circular 12 pt semibold SF Symbols (clock, checkmark.circle, nosign) are ~13.5 pt wide.
    private static let conservativeIconWidth: CGFloat = 16
    private static let compactIconWidth: CGFloat = 13
    private static let horizontalSafetyMargin: CGFloat = 8
    private static let verticalSafetyMargin: CGFloat = 3

    private static let timeLineHeight: CGFloat = measureLineHeight(
        size: ScheduleCardStyle.timeFontSize, monospacedDigits: true)
    private static let labelLineHeight: CGFloat = measureLineHeight(
        size: ScheduleCardStyle.labelFontSize, monospacedDigits: false)
    private static let compactTimeLineHeight: CGFloat = measureLineHeight(
        size: ScheduleCardStyle.compactTimeFontSize, monospacedDigits: true)
    private static let compactLabelLineHeight: CGFloat = measureLineHeight(
        size: ScheduleCardStyle.compactLabelFontSize, monospacedDigits: false)

    /// Minimum card height where ScheduleCardContent's stacked vertical variant fits.
    static var stackedThresholdHeight: CGFloat {
        // Matches VStack(spacing: 2): 4 pt spacer + 2 + time + 2 + label + 2 (before bottom Spacer).
        ceil(
            ScheduleCardStyle.stackedTopSpacerHeight
                + ScheduleCardStyle.stackedSpacing * 3
                + timeLineHeight
                + labelLineHeight
        ) + 2
    }

    /// Minimum card height where the compact 2-line stack fits (30 min cards qualify; 15-20 min stay horizontal).
    static var compactStackedThresholdHeight: CGFloat {
        ceil(
            compactTimeLineHeight
                + ScheduleCardStyle.compactStackedSpacing
                + compactLabelLineHeight
        ) + 2
    }

    /// Protected height of the top-aligned stacked variant, including vertical safety margin.
    static var stackedContentHeight: CGFloat {
        // Ink ends after the label row; the trailing Spacer is empty.
        ceil(
            ScheduleCardStyle.stackedTopSpacerHeight
                + ScheduleCardStyle.stackedSpacing * 2
                + timeLineHeight
                + labelLineHeight
        ) + verticalSafetyMargin
    }

    func canCompactStack(cardHeight: CGFloat) -> Bool {
        cardHeight >= Self.compactStackedThresholdHeight
            && cardHeight < Self.stackedThresholdHeight
    }

    func timeRowWidth(start: Date, usesCompactTime: Bool, usesCompactStack: Bool) -> CGFloat {
        let timeText = ScheduleCardStyle.formattedTime(start, compact: usesCompactTime)
        let fontSize =
            usesCompactStack
            ? ScheduleCardStyle.compactTimeFontSize : ScheduleCardStyle.timeFontSize
        let iconWidth = usesCompactStack ? Self.compactIconWidth : Self.conservativeIconWidth
        return iconWidth
            + ScheduleCardStyle.timeIconSpacing
            + Self.measureTextWidth(
                timeText,
                size: fontSize,
                tracking: ScheduleCardStyle.timeTracking,
                monospacedDigits: true)
    }

    func bounds(
        start: Date,
        label: String,
        cardHeight: CGFloat,
        usesCompactTime: Bool = false,
        usesCompactStack: Bool = false
    ) -> Bounds {
        let isStacked = cardHeight >= Self.stackedThresholdHeight
        let effectiveCompactStack = !isStacked && usesCompactStack && canCompactStack(cardHeight: cardHeight)

        let timeWidth = timeRowWidth(
            start: start,
            usesCompactTime: usesCompactTime,
            usesCompactStack: effectiveCompactStack
        )
        let labelFontSize =
            effectiveCompactStack
            ? ScheduleCardStyle.compactLabelFontSize : ScheduleCardStyle.labelFontSize
        let labelWidth = Self.measureTextWidth(
            label,
            size: labelFontSize,
            tracking: 0,
            monospacedDigits: false)

        let rawWidth: CGFloat
        let height: CGFloat
        if isStacked {
            rawWidth = max(timeWidth, labelWidth)
            height = min(cardHeight, Self.stackedContentHeight)
        } else if effectiveCompactStack {
            rawWidth = max(timeWidth, labelWidth)
            height = cardHeight
        } else {
            rawWidth = timeWidth + ScheduleCardStyle.compactHorizontalSpacing + labelWidth
            height = cardHeight
        }

        let width =
            ScheduleCardStyle.horizontalPadding
            + ceil(rawWidth)
            + Self.horizontalSafetyMargin
        return Bounds(width: width, height: max(height, 0), isStacked: isStacked)
    }

    private static func makeSemiboldSystemFont(size: CGFloat, monospacedDigits: Bool) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
        // 0.23 matches UIFont.Weight.semibold without importing UIKit.
        var attributes: [CFString: Any] = [
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.23 as CGFloat]
        ]
        if monospacedDigits {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [
                    kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                    kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
                ]
            ]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    }

    private static func measureLineHeight(size: CGFloat, monospacedDigits: Bool) -> CGFloat {
        let font = makeSemiboldSystemFont(size: size, monospacedDigits: monospacedDigits)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    private static func measureTextWidth(
        _ string: String,
        size: CGFloat,
        tracking: CGFloat,
        monospacedDigits: Bool
    ) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let font = makeSemiboldSystemFont(size: size, monospacedDigits: monospacedDigits)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        if tracking != 0 {
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
        }
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
