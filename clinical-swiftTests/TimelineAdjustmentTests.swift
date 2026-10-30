import ClinicalModels
import CoreGraphics
import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct TimelineAdjustmentTests {
    @Test(arguments: [false, true])
    func touchWithoutMovementKeepsStoredTimeAndDuration(unavailable: Bool) throws {
        let start = try Date("2026-10-25T11:07:00Z", strategy: .iso8601)
        var draft: TimelineItem =
            unavailable
            ? .unavailableTime(UnavailableTime(start: start, durationMinutes: 23))
            : .appointment(
                Appointment(
                    patientName: "Patient", start: start, durationMinutes: 23, status: .scheduled))
        withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            for edge in [TimelineAdjustment.Edge.move, .duration] {
                model.begin(draft, edge: edge, items: [draft])
                model.update(&draft, translation: 0, items: [draft])
                model.release()
                #expect(draft.start == start)
                #expect(draft.durationMinutes == 23)
            }
        }
    }

    @Test func unavailableTimeKeepsItsTypeLabelAndIdentityThroughMoveAndResize() throws {
        let appointment = try appointment()
        let block = UnavailableTime(
            id: appointment.id, label: "Travel", start: appointment.start, durationMinutes: 30)
        let items: [TimelineItem] = [.appointment(appointment), .unavailableTime(block)]
        var draft = TimelineItem.unavailableTime(block)
        try withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            model.begin(draft, edge: .move, items: items)
            model.update(&draft, translation: 13, items: items)
            model.release()
            #expect(draft.start.timeOfDay == TimeOfDay(12, 15))
            model.begin(draft, edge: .duration, items: items)
            model.update(&draft, translation: -100, items: items)
            model.release()
            guard case .unavailableTime(let preview) = draft else {
                Issue.record("The adjustment must remain unavailable time.")
                return
            }
            #expect(preview.id == block.id)
            #expect(preview.label == block.label)
            #expect(preview.start.timeOfDay == TimeOfDay(12, 15))
            #expect(preview.durationMinutes == 15)
            let engine = TimelineLayoutEngine(
                availableWidth: 400, scale: TimelineScale(items: items))
            let layout = try #require(
                engine.layout(items: items, floatingID: .unavailableTime(block.id))
                    .first { $0.id == .unavailableTime(block.id) })
            #expect(layout.rect.width == Timeline.metrics.contentWidth(availableWidth: 400))
        }
    }

    @Test func unavailableTimeUsesTheSameBreakDwellAndScrollCorrection() throws {
        let block = UnavailableTime(
            label: "Travel", start: try appointment().start, durationMinutes: 30)
        var draft = TimelineItem.unavailableTime(block)
        let items = [draft]
        withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            model.begin(draft, edge: .move, items: items)
            model.update(&draft, translation: 76, items: items)
            #expect(model.hoverRequest != nil)
            #expect(!model.scale(items, draft: draft).isBreakExpanded)
            let start = draft.start
            #expect(model.expandBreak(draft: draft, items: items) > 0)
            #expect(model.scale(items, draft: draft).isBreakExpanded)
            #expect(draft.start == start)
            model.update(&draft, translation: 200, items: items)
            #expect(!model.scale(items, draft: draft).isBreakExpanded)
        }
    }

    private func appointment(hour: Int = 12, minute: Int = 0) throws -> Appointment {
        Appointment(
            patientName: "Patient",
            start: try Date("2026-10-25T00:00:00Z", strategy: .iso8601).setTime(hour, minute),
            durationMinutes: 30, status: .scheduled)
    }

    @Test func scaleRoundTripsEveryFiveMinutes() {
        for presentation in [TimelineScale.BreakPresentation.compact, .expanded] {
            let scale = TimelineScale(items: [], breakPresentation: presentation)
            for minute in stride(from: 9 * 60, through: 21 * 60, by: 5) {
                let time = TimeOfDay(minute / 60, minute % 60)
                #expect(scale.time(at: scale.yOffset(for: time)) == time)
            }
        }
    }

    @Test func movingSnapsAndKeepsDuration() throws {
        var draft = TimelineItem.appointment(try appointment())
        let items = [draft]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: items)
        model.update(&draft, translation: 13, items: items)
        #expect(draft.start.timeOfDay == TimeOfDay(12, 15))
        #expect(draft.durationMinutes == 30)
        model.release()
        #expect(draft.start.timeOfDay == TimeOfDay(12, 15))
    }

    @Test func durationHandleKeepsStartAndMinimumDuration() throws {
        let appointment = try appointment()
        var draft = TimelineItem.appointment(appointment)
        let items = [draft]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .duration, items: items)
        model.update(&draft, translation: -100, items: items)
        #expect(draft.start == appointment.start)
        #expect(draft.durationMinutes == 15)
    }

    @Test func passingBreakCancelsExpansion() throws {
        var draft = TimelineItem.appointment(try appointment())
        let items = [draft]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: items)
        model.update(&draft, translation: 76, items: items)
        #expect(model.hoverRequest != nil)
        #expect(!model.scale(items, draft: draft).isBreakExpanded)
        model.update(&draft, translation: 105, items: items)
        #expect(model.hoverRequest == nil)
        #expect(model.expandBreak(draft: draft, items: items) == 0)
        #expect(!model.scale(items, draft: draft).isBreakExpanded)
        #expect(draft.start.timeOfDay == TimeOfDay(16, 15))
    }

    @Test func dwellExpandsAndExitCollapsesWithoutChangingTime() throws {
        var draft = TimelineItem.appointment(try appointment())
        let items = [draft]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: items)
        model.update(&draft, translation: 76, items: items)
        let time = draft.start
        let correction = model.expandBreak(draft: draft, items: items)
        #expect(correction > 0)
        #expect(model.scale(items, draft: draft).isBreakExpanded)
        #expect(draft.start == time)
        model.update(&draft, translation: 76, items: items)
        #expect(draft.start == time)
        model.update(&draft, translation: 200, items: items)
        #expect(!model.scale(items, draft: draft).isBreakExpanded)
        #expect(draft.start.timeOfDay == TimeOfDay(16, 35))
    }

    @Test func otherBreakAppointmentsKeepBreakExpanded() throws {
        let appointment = try appointment(hour: 14)
        let other = try self.appointment(hour: 15)
        var draft = TimelineItem.appointment(appointment)
        let items = [appointment, other].map(TimelineItem.appointment)
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: items)
        model.update(&draft, translation: -100, items: items)
        #expect(draft.start.timeOfDay == TimeOfDay(12, 20))
        #expect(model.scale(items, draft: draft).isBreakExpanded)
    }

    @Test func releaseWithoutMotionClearsDragStateAndOriginal() throws {
        let appointment = try appointment()
        let draft = TimelineItem.appointment(appointment)
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: [draft])
        model.release()
        #expect(!model.isDragging)
        #expect(model.original == nil)
    }

    @Test func nextGestureStartsFromCurrentDraft() throws {
        var draft = TimelineItem.appointment(try appointment())
        let items = [draft]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(draft, edge: .move, items: items)
        model.update(&draft, translation: 15, items: items)
        model.release()
        #expect(draft.start.timeOfDay == TimeOfDay(12, 15))
        model.begin(draft, edge: .duration, items: items)
        model.update(&draft, translation: 10, items: items)
        #expect(draft.start.timeOfDay == TimeOfDay(12, 15))
        #expect(draft.durationMinutes == 40)
        model.release()
        #expect(!model.isDragging)
    }

    @Test func floatingCardUsesFullWidthAndLeavesOtherCardsInTheirOwnColumns() throws {
        let appointment = try appointment()
        let other = try self.appointment(minute: 15)
        let items = [appointment, other].map(TimelineItem.appointment)
        let engine = TimelineLayoutEngine(availableWidth: 400, scale: TimelineScale(items: items))
        let layouts = engine.layout(items: items, floatingID: .appointment(appointment.id))
        let floating = try #require(layouts.first { $0.id == .appointment(appointment.id) })
        let regular = try #require(layouts.first { $0.id == .appointment(other.id) })
        #expect(floating.rect.width == Timeline.metrics.contentWidth(availableWidth: 400))
        #expect(floating.rect.minX == Timeline.metrics.contentLeadingInset)
        #expect(regular.rect.width == floating.rect.width)
    }
}
