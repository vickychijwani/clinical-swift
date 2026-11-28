import ClinicalModels
import CoreGraphics
import CoreText
import Foundation

nonisolated enum ScheduleCardStyle {
    struct Configuration: Equatable, Sendable {
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let horizontalPadding: CGFloat
        let stackedTopSpacerHeight: CGFloat
        let stackedSpacing: CGFloat
        let compactStackedSpacing: CGFloat
        let compactHorizontalSpacing: CGFloat
        let timeIconSpacing: CGFloat
        let timeTracking: CGFloat
        let timeFontSize: CGFloat
        let labelFontSize: CGFloat
        let iconWidth: CGFloat
        let compactTimeFontSize: CGFloat
        let compactLabelFontSize: CGFloat
        let compactIconWidth: CGFloat
        let horizontalTimeFontSize: CGFloat
        let horizontalLabelFontSize: CGFloat
        let horizontalIconWidth: CGFloat

        static let standard = Configuration(
            cornerRadius: 8,
            borderWidth: 2,
            horizontalPadding: 8,
            stackedTopSpacerHeight: 4,
            stackedSpacing: 2,
            compactStackedSpacing: 0,
            compactHorizontalSpacing: 8,
            timeIconSpacing: 2,
            timeTracking: 0.4,
            timeFontSize: 12,
            labelFontSize: 14,
            iconWidth: 16,
            compactTimeFontSize: 10,
            compactLabelFontSize: 12,
            compactIconWidth: 13,
            horizontalTimeFontSize: 12,
            horizontalLabelFontSize: 14,
            horizontalIconWidth: 16
        )

        static let widget = Configuration(
            cornerRadius: 6,
            borderWidth: 1,
            horizontalPadding: 5,
            stackedTopSpacerHeight: 2,
            stackedSpacing: 1,
            compactStackedSpacing: 0,
            compactHorizontalSpacing: 5,
            timeIconSpacing: 2,
            timeTracking: 0.2,
            timeFontSize: 10,
            labelFontSize: 11.5,
            iconWidth: 13,
            compactTimeFontSize: 9,
            compactLabelFontSize: 10.5,
            compactIconWidth: 11.5,
            horizontalTimeFontSize: 9,
            horizontalLabelFontSize: 10,
            horizontalIconWidth: 11.5
        )
    }

    static let cornerRadius: CGFloat = Configuration.standard.cornerRadius
    static let horizontalPadding: CGFloat = Configuration.standard.horizontalPadding
    static let stackedTopSpacerHeight: CGFloat = Configuration.standard.stackedTopSpacerHeight
    static let stackedSpacing: CGFloat = Configuration.standard.stackedSpacing
    static let compactStackedSpacing: CGFloat = Configuration.standard.compactStackedSpacing
    static let compactHorizontalSpacing: CGFloat = Configuration.standard.compactHorizontalSpacing
    static let timeIconSpacing: CGFloat = Configuration.standard.timeIconSpacing
    static let timeFontSize: CGFloat = Configuration.standard.timeFontSize
    static let timeTracking: CGFloat = Configuration.standard.timeTracking
    static let labelFontSize: CGFloat = Configuration.standard.labelFontSize
    static let compactTimeFontSize: CGFloat = Configuration.standard.compactTimeFontSize
    static let compactLabelFontSize: CGFloat = Configuration.standard.compactLabelFontSize

    static func formattedTime(_ date: Date, compact: Bool) -> String {
        if compact {
            return date.formatted(
                ClinicDate.formatStyle.hour(.defaultDigits(amPM: .omitted)).minute())
        }
        return date.formatted(ClinicDate.formatStyle.hour().minute())
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
            style(for: .standard)
        }

        func style(for configuration: ScheduleCardStyle.Configuration) -> Style {
            switch self {
            case .stacked:
                Style(
                    timeFontSize: configuration.timeFontSize,
                    labelFontSize: configuration.labelFontSize,
                    iconWidth: configuration.iconWidth,
                    spacing: configuration.stackedSpacing,
                    topSpacerHeight: configuration.stackedTopSpacerHeight
                )
            case .compactStacked:
                Style(
                    timeFontSize: configuration.compactTimeFontSize,
                    labelFontSize: configuration.compactLabelFontSize,
                    iconWidth: configuration.compactIconWidth,
                    spacing: configuration.compactStackedSpacing,
                    topSpacerHeight: 0
                )
            case .horizontal:
                Style(
                    timeFontSize: configuration.horizontalTimeFontSize,
                    labelFontSize: configuration.horizontalLabelFontSize,
                    iconWidth: configuration.horizontalIconWidth,
                    spacing: configuration.compactHorizontalSpacing,
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

    /// Wraps an immutable CoreText font so cached metrics stay Sendable without importing UIKit.
    private struct CachedFont: @unchecked Sendable {
        let ctFont: CTFont
    }

    static let standard = ScheduleCardContentMetrics(configuration: .standard)
    static let widget = ScheduleCardContentMetrics(configuration: .widget)

    private static let horizontalSafetyMargin: CGFloat = 8
    private static let verticalSafetyMargin: CGFloat = 3

    let configuration: ScheduleCardStyle.Configuration
    private let timeFont: CachedFont
    private let labelFont: CachedFont
    private let compactTimeFont: CachedFont
    private let compactLabelFont: CachedFont
    private let horizontalTimeFont: CachedFont
    private let horizontalLabelFont: CachedFont
    private let timeLineHeight: CGFloat
    private let labelLineHeight: CGFloat
    private let compactTimeLineHeight: CGFloat
    private let compactLabelLineHeight: CGFloat

    init(configuration: ScheduleCardStyle.Configuration = .standard) {
        self.configuration = configuration
        let timeFont = Self.makeSemiboldSystemFont(
            size: configuration.timeFontSize, monospacedDigits: true)
        let labelFont = Self.makeSemiboldSystemFont(
            size: configuration.labelFontSize, monospacedDigits: false)
        let compactTimeFont = Self.makeSemiboldSystemFont(
            size: configuration.compactTimeFontSize, monospacedDigits: true)
        let compactLabelFont = Self.makeSemiboldSystemFont(
            size: configuration.compactLabelFontSize, monospacedDigits: false)
        let horizontalTimeFont = Self.makeSemiboldSystemFont(
            size: configuration.horizontalTimeFontSize, monospacedDigits: true)
        let horizontalLabelFont = Self.makeSemiboldSystemFont(
            size: configuration.horizontalLabelFontSize, monospacedDigits: false)

        self.timeFont = CachedFont(ctFont: timeFont)
        self.labelFont = CachedFont(ctFont: labelFont)
        self.compactTimeFont = CachedFont(ctFont: compactTimeFont)
        self.compactLabelFont = CachedFont(ctFont: compactLabelFont)
        self.horizontalTimeFont = CachedFont(ctFont: horizontalTimeFont)
        self.horizontalLabelFont = CachedFont(ctFont: horizontalLabelFont)
        self.timeLineHeight = Self.lineHeight(of: timeFont)
        self.labelLineHeight = Self.lineHeight(of: labelFont)
        self.compactTimeLineHeight = Self.lineHeight(of: compactTimeFont)
        self.compactLabelLineHeight = Self.lineHeight(of: compactLabelFont)
    }

    static var stackedThresholdHeight: CGFloat {
        standard.stackedThresholdHeight
    }

    static var compactStackedThresholdHeight: CGFloat {
        standard.compactStackedThresholdHeight
    }

    static var stackedContentHeight: CGFloat {
        standard.stackedContentHeight
    }

    /// Minimum card height where ScheduleCardContent's stacked vertical variant fits.
    var stackedThresholdHeight: CGFloat {
        // Matches VStack(spacing: 2): 4 pt spacer + 2 + time + 2 + label + 2 (before bottom Spacer).
        ceil(
            configuration.stackedTopSpacerHeight
                + configuration.stackedSpacing * 3
                + timeLineHeight
                + labelLineHeight
        ) + 2
    }

    /// Minimum card height where the compact 2-line stack fits (30 min cards qualify; 15-20 min stay horizontal).
    var compactStackedThresholdHeight: CGFloat {
        ceil(
            compactTimeLineHeight
                + configuration.compactStackedSpacing
                + compactLabelLineHeight
        ) + 2
    }

    /// Protected height of the top-aligned stacked variant, including vertical safety margin.
    var stackedContentHeight: CGFloat {
        // Ink ends after the label row; the trailing Spacer is empty.
        ceil(
            configuration.stackedTopSpacerHeight
                + configuration.stackedSpacing * 2
                + timeLineHeight
                + labelLineHeight
        ) + Self.verticalSafetyMargin
    }

    func defaultLayout(cardHeight: CGFloat) -> ScheduleCardPresentation.Layout {
        cardHeight >= stackedThresholdHeight ? .stacked : .horizontal
    }

    func defaultPresentation(cardHeight: CGFloat) -> ScheduleCardPresentation {
        ScheduleCardPresentation(layout: defaultLayout(cardHeight: cardHeight))
    }

    func canCompactStack(cardHeight: CGFloat) -> Bool {
        cardHeight >= compactStackedThresholdHeight
            && cardHeight < stackedThresholdHeight
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
        let horizontalPaddingTotal = configuration.horizontalPadding * 2
        let minimumCompactTime = minimum?.usesCompactTime ?? false

        if cardHeight >= stackedThresholdHeight {
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
                    presentation: ScheduleCardPresentation(
                        layout: .horizontal, usesCompactTime: false)
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
        let style = layout.style(for: configuration)
        let timeText = ScheduleCardStyle.formattedTime(start, compact: usesCompactTime)
        return style.iconWidth
            + configuration.timeIconSpacing
            + Self.measureTextWidth(
                timeText,
                font: timeFont(for: layout),
                tracking: configuration.timeTracking)
    }

    func bounds(
        start: Date,
        label: String,
        cardHeight: CGFloat,
        presentation: ScheduleCardPresentation? = nil
    ) -> Bounds {
        let resolved = presentation ?? defaultPresentation(cardHeight: cardHeight)
        let style = resolved.layout.style(for: configuration)

        let timeWidth = timeRowWidth(
            start: start,
            layout: resolved.layout,
            usesCompactTime: resolved.usesCompactTime
        )
        let labelWidth = Self.measureTextWidth(
            label,
            font: labelFont(for: resolved.layout),
            tracking: 0)

        let rawWidth: CGFloat
        let height: CGFloat
        switch resolved.layout {
        case .stacked:
            rawWidth = max(timeWidth, labelWidth)
            height = min(cardHeight, stackedContentHeight)
        case .compactStacked:
            rawWidth = max(timeWidth, labelWidth)
            height = cardHeight
        case .horizontal:
            rawWidth = timeWidth + style.spacing + labelWidth
            height = cardHeight
        }

        let width =
            configuration.horizontalPadding
            + ceil(rawWidth)
            + Self.horizontalSafetyMargin
        return Bounds(width: width, height: max(height, 0))
    }

    private func timeFont(for layout: ScheduleCardPresentation.Layout) -> CTFont {
        switch layout {
        case .stacked: timeFont.ctFont
        case .compactStacked: compactTimeFont.ctFont
        case .horizontal: horizontalTimeFont.ctFont
        }
    }

    private func labelFont(for layout: ScheduleCardPresentation.Layout) -> CTFont {
        switch layout {
        case .stacked: labelFont.ctFont
        case .compactStacked: compactLabelFont.ctFont
        case .horizontal: horizontalLabelFont.ctFont
        }
    }

    private static func makeSemiboldSystemFont(size: CGFloat, monospacedDigits: Bool) -> CTFont {
        let base =
            CTFontCreateUIFontForLanguage(.system, size, nil)
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

    private static func lineHeight(of font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    private static func measureTextWidth(
        _ string: String,
        font: CTFont,
        tracking: CGFloat
    ) -> CGFloat {
        guard !string.isEmpty else { return 0 }
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
