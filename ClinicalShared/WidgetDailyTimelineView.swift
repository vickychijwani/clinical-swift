import AppIntents
import ClinicalModels
import SwiftUI

struct WidgetDailyTimelineContentView: View {
    let snapshot: WidgetDaySnapshot
    let entryDate: Date

    private static let widgetTuning: ScheduleCardTuning = {
        var tuning = ScheduleCardTuning()
        tuning.overlap = .widget
        return tuning
    }()

    var body: some View {
        VStack(spacing: 6) {
            WidgetDailyTimelineHeaderView(snapshot: snapshot)

            if snapshot.isSunday && snapshot.items.isEmpty {
                WidgetDailyTimelineVacationView(day: snapshot.day)
            } else {
                WidgetDailyTimelineCanvasView(
                    snapshot: snapshot,
                    entryDate: entryDate
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .environment(\.scheduleCardStyle, .widget)
        .environment(\.scheduleCardTuning, Self.widgetTuning)
    }
}

private struct WidgetDailyTimelineHeaderView: View {
    let snapshot: WidgetDaySnapshot

    var body: some View {
        HStack(spacing: 6) {
            if let destination = ClinicalURL.schedule(snapshot.day).url {
                Link(destination: destination) {
                    dateLabel
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                dateLabel
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }

            HStack(spacing: 4) {
                if !snapshot.isToday {
                    Button(intent: ResetDailyTimelineToTodayIntent()) {
                        Text("Today")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color.accentColor.opacity(0.12), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }

                Button(intent: StepDailyTimelineDayIntent(delta: -1)) {
                    WidgetHeaderIcon(systemImage: "chevron.left", title: "Previous Day")
                }
                .buttonStyle(.plain)

                Button(intent: StepDailyTimelineDayIntent(delta: 1)) {
                    WidgetHeaderIcon(systemImage: "chevron.right", title: "Next Day")
                }
                .buttonStyle(.plain)

                if let bookURL = ClinicalURL.bookAppointment(snapshot.day).url {
                    Link(destination: bookURL) {
                        WidgetHeaderIcon(
                            systemImage: "plus",
                            title: "Book Appointment",
                            isAccented: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateLabel: some View {
        Text(
            snapshot.date,
            format: ClinicDate.formatStyle.weekday(.wide).day().month(.abbreviated)
        )
        .textCase(.uppercase)
        .font(.caption.bold())
        .foregroundStyle(snapshot.isToday ? Color.accentColor : Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct WidgetHeaderIcon: View {
    let systemImage: String
    let title: String
    var isAccented = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.caption2.bold())
            .foregroundStyle(isAccented ? Color.accentColor : Color.secondary)
            .frame(width: 24, height: 24)
            .background(
                isAccented ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06),
                in: .circle
            )
            .contentShape(.circle)
    }
}

private struct WidgetDailyTimelineVacationView: View {
    let day: ScheduleDay

    var body: some View {
        ZStack {
            if let destination = ClinicalURL.schedule(day).url {
                Link(destination: destination) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Text("Vacation day 🌻")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetDailyTimelineCanvasView: View {
    let snapshot: WidgetDaySnapshot
    let entryDate: Date

    var body: some View {
        GeometryReader { geometry in
            let scale = TimelineScale.widget(
                items: snapshot.items,
                now: snapshot.isToday ? entryDate : nil,
                availableHeight: geometry.size.height
            )
            let engine = TimelineLayoutEngine(
                availableWidth: geometry.size.width,
                scale: scale,
                overlap: .widget,
                contentMetrics: ScheduleCardContentMetrics(configuration: .widget),
                assertOnFallback: false
            )
            let layouts = engine.layout(items: snapshot.items)
            let cornerRadius = ScheduleCardStyle.Configuration.widget.cornerRadius

            ZStack(alignment: .topLeading) {
                if let destination = ClinicalURL.schedule(snapshot.day).url {
                    Link(destination: destination) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .topLeading) {
                    TimelineBreakView(
                        scale: scale,
                        availableWidth: geometry.size.width,
                        style: .widget
                    )

                    TimelineHourGrid(
                        scale: scale,
                        availableWidth: geometry.size.width,
                        style: .widget
                    )

                    ForEach(layouts) { layout in
                        if let destination = layout.item.widgetURL(using: ClinicDate.calendar) {
                            Link(destination: destination) {
                                ScheduleItemCard(
                                    item: layout.item,
                                    contentTrailingInset: layout.contentTrailingInset,
                                    presentation: layout.presentation
                                )
                                .frame(width: layout.rect.width, height: layout.rect.height)
                                .contentShape(.rect(cornerRadius: cornerRadius))
                                .clipShape(.rect(cornerRadius: cornerRadius))
                            }
                            .buttonStyle(.plain)
                            .modifier(
                                TimelineCardOverlapSeparation(isActive: layout.isOverlappingFront)
                            )
                            .zIndex(Double(layout.zIndex))
                            .position(x: layout.rect.midX, y: layout.rect.midY)
                        }
                    }

                    if snapshot.isToday, scale.showsTime(entryDate.timeOfDay) {
                        NowMarkerView(
                            availableWidth: geometry.size.width,
                            metrics: scale.metrics,
                            indicator: .dot(size: 7)
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: scale.yOffset(for: entryDate.timeOfDay)
                        )
                        .zIndex(Double(layouts.count + 2))
                    }
                }
                .frame(
                    width: geometry.size.width, height: scale.totalHeight, alignment: .topLeading
                )
                .padding(.vertical, scale.metrics.verticalPadding)
            }
        }
    }
}
