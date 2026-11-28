import SwiftUI

struct ScheduleCard: View {
    @Environment(\.scheduleCardTuning) private var tuning
    @Environment(\.scheduleCardStyle) private var cardStyle

    let start: Date
    let label: String
    let appearance: Appearance
    var isDeemphasized = false
    /// Extra trailing inset computed by the timeline layout engine so content cannot extend under a front card.
    var contentTrailingInset: CGFloat = 0
    /// Explicit layout and time-format choice shared with TimelineLayoutEngine.
    var presentation: ScheduleCardPresentation? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch appearance.background {
            case .color(let color):
                RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                    .fill(color)
            case .draft:
                RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                    .fill(AppColor.activeCard)
                    // Keep underlying card edges visible as possible conflict cues.
                    .opacity(tuning.surfaceOpacity)
            }

            ScheduleCardContent(
                start: start,
                label: label,
                appearance: appearance,
                presentation: presentation
            )
            .padding(.leading, cardStyle.horizontalPadding)
            // Let overflowing text reach the card border unless a front card fences the trailing edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .padding(.trailing, contentTrailingInset)
            .opacity(
                appearance.contentOpacity * (isDeemphasized ? tuning.otherContentOpacity : 1))

            if appearance.usesInnerBorder {
                RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                    .strokeBorder(appearance.border, style: appearance.borderStyle)
            } else {
                RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                    .stroke(appearance.border, style: appearance.borderStyle)
            }
        }
        .clipShape(.rect(cornerRadius: cardStyle.cornerRadius))
    }

    struct Appearance {
        let systemImage: String
        let background: Background
        let border: Color
        let borderStyle: StrokeStyle
        var usesInnerBorder = false
        var contentOpacity: Double = 1
        var timeColor: Color? = nil
        var labelColor: Color? = nil
    }

    enum Background {
        case color(Color)
        case draft
    }
}

struct ScheduleCardLift: ViewModifier {
    @Environment(\.appPalette) private var palette
    @Environment(\.scheduleCardTuning) private var tuning
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                    .fill(.black)
                    .shadow(
                        color: palette[.shadow].opacity(tuning.lift.shadowOpacity),
                        radius: isPressed ? tuning.lift.shadowRadius : 0,
                        y: isPressed ? 3 : 0
                    )
                    .overlay {
                        // Remove the shadow's interior so it cannot darken the translucent fill.
                        RoundedRectangle(cornerRadius: ScheduleCardStyle.cornerRadius)
                            .fill(.black)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .opacity(isPressed ? 1 : 0)
                    .allowsHitTesting(false)
            }
            // Keep the time edges fixed. Height and vertical position communicate the interval.
            .scaleEffect(x: isPressed ? 1 + tuning.lift.width : 1, y: 1)
            .animation(
                AppMotion.animation(.smooth(duration: tuning.lift.duration)), value: isPressed)
    }
}

private struct ScheduleCardContent: View {
    @Environment(\.scheduleCardStyle) private var cardStyle

    let start: Date
    let label: String
    let appearance: ScheduleCard.Appearance
    let presentation: ScheduleCardPresentation?

    var body: some View {
        if let presentation {
            content(for: presentation)
        } else {
            ViewThatFits(in: .vertical) {
                // Preferred: vertical layout when there's enough height
                content(for: ScheduleCardPresentation(layout: .stacked))

                // Fallback vertical layout with slightly less spacing
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    ScheduleCardTime(start: start, appearance: appearance)
                    ScheduleCardLabel(label: label, color: appearance.labelColor)
                    Spacer(minLength: 0)
                }

                // Fallback: horizontal layout when vertical doesn't fit
                content(for: ScheduleCardPresentation(layout: .horizontal))
            }
        }
    }

    @ViewBuilder
    private func content(for presentation: ScheduleCardPresentation) -> some View {
        let style = presentation.layout.style(for: cardStyle)
        switch presentation.layout {
        case .stacked:
            VStack(alignment: .leading, spacing: style.spacing) {
                Color.clear.frame(height: style.topSpacerHeight)
                ScheduleCardTime(
                    start: start,
                    appearance: appearance,
                    usesCompactTime: presentation.usesCompactTime,
                    fontSize: style.timeFontSize
                )
                ScheduleCardLabel(
                    label: label,
                    color: appearance.labelColor,
                    fontSize: style.labelFontSize
                )
                Spacer(minLength: 0)
            }
        case .compactStacked:
            // Compact 2-line stack for narrow medium cards (e.g. 30 min) so names stay readable.
            VStack(alignment: .leading, spacing: style.spacing) {
                Spacer(minLength: 0)
                ScheduleCardTime(
                    start: start,
                    appearance: appearance,
                    usesCompactTime: presentation.usesCompactTime,
                    fontSize: style.timeFontSize
                )
                ScheduleCardLabel(
                    label: label,
                    color: appearance.labelColor,
                    fontSize: style.labelFontSize
                )
                Spacer(minLength: 0)
            }
        case .horizontal:
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: style.spacing) {
                    ScheduleCardTime(
                        start: start,
                        appearance: appearance,
                        usesCompactTime: presentation.usesCompactTime,
                        fontSize: style.timeFontSize
                    )
                    ScheduleCardLabel(
                        label: label,
                        color: appearance.labelColor,
                        fontSize: style.labelFontSize
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ScheduleCardTime: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.scheduleCardStyle) private var cardStyle
    let start: Date
    let appearance: ScheduleCard.Appearance
    var usesCompactTime = false
    var fontSize: CGFloat? = nil

    var body: some View {
        HStack(spacing: cardStyle.timeIconSpacing) {
            Image(systemName: appearance.systemImage)
                .foregroundStyle(appearance.timeColor ?? palette[.cardIcon])
            Text(ScheduleCardStyle.formattedTime(start, compact: usesCompactTime))
        }
        .font(
            .system(size: fontSize ?? cardStyle.timeFontSize, weight: .semibold).monospacedDigit()
        )
        .foregroundStyle(appearance.timeColor ?? palette[.time])
        .tracking(cardStyle.timeTracking)
        .layoutPriority(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ScheduleCardLabel: View {
    @Environment(\.appPalette) private var palette
    @Environment(\.scheduleCardStyle) private var cardStyle
    let label: String
    let color: Color?
    var fontSize: CGFloat? = nil

    var body: some View {
        Text(label)
            .font(.system(size: fontSize ?? cardStyle.labelFontSize, weight: .semibold))
            .foregroundStyle(color ?? palette[.text])
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .minimumScaleFactor(0.5)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

struct TimelineCardOverlapSeparation: ViewModifier {
    @Environment(\.appPalette) private var palette
    @Environment(\.scheduleCardTuning) private var tuning
    @Environment(\.scheduleCardStyle) private var cardStyle
    let isActive: Bool

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                switch tuning.overlap.separation {
                case .shadow:
                    RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                        .fill(.black)
                        .shadow(
                            color: palette[.shadow].opacity(tuning.overlap.shadowOpacity),
                            radius: tuning.overlap.shadowRadius,
                            y: 2
                        )
                        .overlay {
                            // Remove the shadow interior so translucent fills are not darkened.
                            RoundedRectangle(cornerRadius: cardStyle.cornerRadius)
                                .fill(.black)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .allowsHitTesting(false)
                case .flat:
                    EmptyView()
                }
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var scheduleCardStyle = ScheduleCardStyle.Configuration.standard
}
