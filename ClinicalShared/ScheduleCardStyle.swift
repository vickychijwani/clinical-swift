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

/// Shared card layout and time-format choice used by both layout measurement and SwiftUI rendering.
nonisolated struct ScheduleCardPresentation: Equatable, Sendable {
    enum Layout: Equatable, Sendable {
        case stacked
        /// Use a compact 2-line stack on medium cards (e.g. 30 min) when a single horizontal line would clip.
        case compactStacked
        case horizontal

        var style: Style {
            switch self {
            case .stacked:
                Style(
                    timeFontSize: ScheduleCardStyle.timeFontSize,
                    labelFontSize: ScheduleCardStyle.labelFontSize,
                    iconWidth: 16,
                    spacing: ScheduleCardStyle.stackedSpacing,
                    topSpacerHeight: ScheduleCardStyle.stackedTopSpacerHeight
                )
            case .compactStacked:
                Style(
                    timeFontSize: ScheduleCardStyle.compactTimeFontSize,
                    labelFontSize: ScheduleCardStyle.compactLabelFontSize,
                    iconWidth: 13,
                    spacing: ScheduleCardStyle.compactStackedSpacing,
                    topSpacerHeight: 0
                )
            case .horizontal:
                Style(
                    timeFontSize: ScheduleCardStyle.timeFontSize,
                    labelFontSize: ScheduleCardStyle.labelFontSize,
                    iconWidth: 16,
                    spacing: ScheduleCardStyle.compactHorizontalSpacing,
                    topSpacerHeight: 0
                )
            }
        }
    }

    nonisolated struct Style: Equatable, Sendable {
        let timeFontSize: CGFloat
        let labelFontSize: CGFloat
        // Circular 12 pt semibold SF Symbols (clock, checkmark.circle, nosign) are ~13.5 pt wide.
        let iconWidth: CGFloat
        let spacing: CGFloat
        let topSpacerHeight: CGFloat
    }

    var layout: Layout
    /// Omit AM/PM when horizontal space is tight so start times stay compact and readable.
    var usesCompactTime: Bool

    init(layout: Layout = .horizontal, usesCompactTime: Bool = false) {
        self.layout = layout
        self.usesCompactTime = usesCompactTime
    }
}

/// Conservative content bounds shared by ScheduleCard and TimelineLayoutEngine.
/// Uses CoreText so the layout engine stays independent of SwiftUI.
nonisolated struct ScheduleCardContentMetrics: Sendable {
    struct Bounds: Equatable, Sendable {
        let width: CGFloat
        let height: CGFloat
    }

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

    func defaultLayout(cardHeight: CGFloat) -> ScheduleCardPresentation.Layout {
        cardHeight >= Self.stackedThresholdHeight ? .stacked : .horizontal
    }

    func defaultPresentation(cardHeight: CGFloat) -> ScheduleCardPresentation {
        ScheduleCardPresentation(layout: defaultLayout(cardHeight: cardHeight))
    }

    func canCompactStack(cardHeight: CGFloat) -> Bool {
        cardHeight >= Self.compactStackedThresholdHeight
            && cardHeight < Self.stackedThresholdHeight
    }

    /// Presentations ordered from calmest to most compact for a card at `cardHeight`.
    func candidatePresentations(cardHeight: CGFloat) -> [ScheduleCardPresentation] {
        let baseLayout = defaultLayout(cardHeight: cardHeight)
        if canCompactStack(cardHeight: cardHeight) {
            return [
                ScheduleCardPresentation(layout: .horizontal, usesCompactTime: false),
                ScheduleCardPresentation(layout: .compactStacked, usesCompactTime: false),
                ScheduleCardPresentation(layout: .compactStacked, usesCompactTime: true),
            ]
        }
        return [
            ScheduleCardPresentation(layout: baseLayout, usesCompactTime: false),
            ScheduleCardPresentation(layout: baseLayout, usesCompactTime: true),
        ]
    }

    /// Chooses the calmest presentation whose measured bounds fit `availableWidth`, respecting `minimum`.
    func resolvePresentation(
        start: Date,
        label: String,
        cardHeight: CGFloat,
        availableWidth: CGFloat,
        minimum: ScheduleCardPresentation? = nil
    ) -> ScheduleCardPresentation {
        let horizontalPaddingTotal = ScheduleCardStyle.horizontalPadding * 2
        let minimumCompactTime = minimum?.usesCompactTime ?? false

        if cardHeight >= Self.stackedThresholdHeight {
            // Tall stacked cards keep AM/PM unless needed for text-aware overlap or ultra-narrow columns.
            let fullTimeWidth =
                timeRowWidth(start: start, layout: .stacked, usesCompactTime: false)
                + horizontalPaddingTotal
            let compactTime = minimumCompactTime || availableWidth < fullTimeWidth + 4
            return ScheduleCardPresentation(layout: .stacked, usesCompactTime: compactTime)
        }

        if canCompactStack(cardHeight: cardHeight) {
            // Medium cards (e.g. 30 min) stay 1-line horizontal when the full label fits,
            // and switch to a compact 2-line stack when narrow.
            let requiresCompactStack = minimum?.layout == .compactStacked
            if !requiresCompactStack {
                let fullHorizontalWidth = bounds(
                    start: start,
                    label: label,
                    cardHeight: cardHeight,
                    presentation: ScheduleCardPresentation(layout: .horizontal, usesCompactTime: false)
                ).width
                if fullHorizontalWidth <= availableWidth {
                    return ScheduleCardPresentation(
                        layout: .horizontal, usesCompactTime: minimumCompactTime)
                }
            }
            let compactStackFullTimeWidth =
                timeRowWidth(start: start, layout: .compactStacked, usesCompactTime: false)
                + horizontalPaddingTotal
            let compactTime = minimumCompactTime || availableWidth < compactStackFullTimeWidth + 4
            return ScheduleCardPresentation(layout: .compactStacked, usesCompactTime: compactTime)
        }

        // Short cards (15-20 min) stay 1-line horizontal; drop AM/PM when the name would clip.
        let fullHorizontalWidth = bounds(
            start: start,
            label: label,
            cardHeight: cardHeight,
            presentation: ScheduleCardPresentation(layout: .horizontal, usesCompactTime: false)
        ).width
        let compactTime = minimumCompactTime || availableWidth < fullHorizontalWidth
        return ScheduleCardPresentation(layout: .horizontal, usesCompactTime: compactTime)
    }

    func timeRowWidth(
        start: Date,
        layout: ScheduleCardPresentation.Layout,
        usesCompactTime: Bool
    ) -> CGFloat {
        let style = layout.style
        let timeText = ScheduleCardStyle.formattedTime(start, compact: usesCompactTime)
        return style.iconWidth
            + ScheduleCardStyle.timeIconSpacing
            + Self.measureTextWidth(
                timeText,
                size: style.timeFontSize,
                tracking: ScheduleCardStyle.timeTracking,
                monospacedDigits: true)
    }

    func bounds(
        start: Date,
        label: String,
        cardHeight: CGFloat,
        presentation: ScheduleCardPresentation? = nil
    ) -> Bounds {
        let resolved = presentation ?? defaultPresentation(cardHeight: cardHeight)
        let style = resolved.layout.style

        let timeWidth = timeRowWidth(
            start: start,
            layout: resolved.layout,
            usesCompactTime: resolved.usesCompactTime
        )
        let labelWidth = Self.measureTextWidth(
            label,
            size: style.labelFontSize,
            tracking: 0,
            monospacedDigits: false)

        let rawWidth: CGFloat
        let height: CGFloat
        switch resolved.layout {
        case .stacked:
            rawWidth = max(timeWidth, labelWidth)
            height = min(cardHeight, Self.stackedContentHeight)
        case .compactStacked:
            rawWidth = max(timeWidth, labelWidth)
            height = cardHeight
        case .horizontal:
            rawWidth = timeWidth + style.spacing + labelWidth
            height = cardHeight
        }

        let width =
            ScheduleCardStyle.horizontalPadding
            + ceil(rawWidth)
            + Self.horizontalSafetyMargin
        return Bounds(width: width, height: max(height, 0))
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
