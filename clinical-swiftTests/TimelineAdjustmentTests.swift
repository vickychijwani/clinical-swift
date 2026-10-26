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
        let item: TimelineItem =
            unavailable
            ? .unavailableTime(UnavailableTime(start: start, durationMinutes: 23))
            : .appointment(
                Appointment(
                    patientName: "Patient", start: start, durationMinutes: 23, status: .scheduled))
        withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            model.select(item)
            for edge in [TimelineAdjustment.Edge.move, .duration] {
                model.begin(item, edge: edge, items: [item])
                model.update(translation: 0, items: [item])
                model.release()
                #expect(model.preview?.start == start)
                #expect(model.preview?.durationMinutes == 23)
            }
        }
    }

    @Test func unavailableTimeKeepsItsTypeLabelAndIdentityThroughMoveResizeAndDateChange() throws {
        let appointment = try appointment()
        let block = UnavailableTime(
            id: appointment.id, label: "Travel", start: appointment.start, durationMinutes: 30)
        let items: [TimelineItem] = [.appointment(appointment), .unavailableTime(block)]
        try withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            model.select(.unavailableTime(block))
            model.begin(.unavailableTime(block), edge: .move, items: items)
            model.update(translation: 13, items: items)
            model.release()
            #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 15))
            model.begin(.unavailableTime(block), edge: .duration, items: items)
            model.update(translation: -100, items: items)
            model.release()
            let nextDate = block.start.date(byAddingDays: 1)
            let moved = try #require(model.selectDate(nextDate))
            guard case .unavailableTime(let preview) = moved else {
                Issue.record("The adjustment must remain unavailable time.")
                return
            }
            #expect(preview.id == block.id)
            #expect(preview.label == block.label)
            #expect(preview.start.timeOfDay == TimeOfDay(12, 15))
            #expect(preview.durationMinutes == 15)
            #expect(model.items(items, on: block.start).map(\.id) == [.appointment(appointment.id)])
            #expect(model.items([], on: nextDate).map(\.id) == [.unavailableTime(block.id)])
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
        let items: [TimelineItem] = [.unavailableTime(block)]
        withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            let model = TimelineAdjustment()
            model.begin(.unavailableTime(block), edge: .move, items: items)
            model.update(translation: 76, items: items)
            #expect(model.hoverRequest != nil)
            #expect(!model.scale(items).isBreakExpanded)
            let start = model.preview?.start
            #expect(model.expandBreak(items: items) > 0)
            #expect(model.scale(items).isBreakExpanded)
            #expect(model.preview?.start == start)
            model.update(translation: 200, items: items)
            #expect(!model.scale(items).isBreakExpanded)
        }
    }

    @Test func doneSavesOnceAndFailureKeepsDraftForRetry() async throws {
        let appointment = try appointment()
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        let items = [TimelineItem.appointment(appointment)]
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: 15, items: items)
        model.release()
        #expect(!model.isSaving)
        let preview = model.preview
        enum SaveError: Error { case failed }
        await model.save { _ in throw SaveError.failed }
        #expect(model.preview?.start == preview?.start)
        #expect(model.preview?.durationMinutes == preview?.durationMinutes)
        #expect(model.isActive)
        #expect(!model.isSaving)
        #expect(model.errorMessage != nil)
        var saved: [TimelineItem] = []
        await model.save { saved.append($0) }
        await model.save { saved.append($0) }
        #expect(saved.count == 1)
        #expect(saved.first?.start == preview?.start)
        #expect(saved.first?.durationMinutes == preview?.durationMinutes)
        #expect(!model.isActive)
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
        let appointment = try appointment()
        let items = [TimelineItem.appointment(appointment)]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: 13, items: items)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 15))
        #expect(model.preview?.durationMinutes == 30)
        model.release()
        #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 15))
        #expect(!model.isSaving)
    }

    @Test func durationHandleKeepsStartAndMinimumDuration() throws {
        let appointment = try appointment()
        let items = [TimelineItem.appointment(appointment)]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .duration, items: items)
        model.update(translation: -100, items: items)
        #expect(model.preview?.start == appointment.start)
        #expect(model.preview?.durationMinutes == 15)
    }

    @Test func passingBreakCancelsExpansion() throws {
        let appointment = try appointment()
        let items = [TimelineItem.appointment(appointment)]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: 76, items: items)
        #expect(model.hoverRequest != nil)
        #expect(!model.scale(items).isBreakExpanded)
        model.update(translation: 105, items: items)
        #expect(model.hoverRequest == nil)
        #expect(model.expandBreak(items: items) == 0)
        #expect(!model.scale(items).isBreakExpanded)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(16, 15))
    }

    @Test func dwellExpandsAndExitCollapsesWithoutChangingTime() throws {
        let appointment = try appointment()
        let items = [TimelineItem.appointment(appointment)]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: 76, items: items)
        let time = model.preview?.start
        let correction = model.expandBreak(items: items)
        #expect(correction > 0)
        #expect(model.scale(items).isBreakExpanded)
        #expect(model.preview?.start == time)
        model.update(translation: 76, items: items)
        #expect(model.preview?.start == time)
        model.update(translation: 200, items: items)
        #expect(!model.scale(items).isBreakExpanded)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(16, 35))
    }

    @Test func otherBreakAppointmentsKeepBreakExpanded() throws {
        let appointment = try appointment(hour: 14)
        let other = try self.appointment(hour: 15)
        let items = [appointment, other].map(TimelineItem.appointment)
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: -100, items: items)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 20))
        #expect(model.scale(items).isBreakExpanded)
    }

    @Test func releaseWithoutMotionDoesNotSave() throws {
        let appointment = try appointment()
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: [.appointment(appointment)])
        model.release()
        #expect(model.selectedID == .appointment(appointment.id))
        #expect(!model.isDragging)
        #expect(!model.isSaving)
        #expect(model.isActive)
    }

    @Test func releaseKeepsModeActiveUntilDone() throws {
        let appointment = try appointment()
        let items = [TimelineItem.appointment(appointment)]
        let model = withDependencies {
            $0.calendar = .autoupdatingCurrent
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: items)
        model.update(translation: 15, items: items)
        model.release()
        #expect(model.isActive)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 15))
        model.begin(.appointment(appointment), edge: .duration, items: items)
        model.update(translation: 10, items: items)
        #expect(model.preview?.start.timeOfDay == TimeOfDay(12, 15))
        #expect(model.preview?.durationMinutes == 40)
        model.finish()
        #expect(!model.isActive)
        #expect(model.selectedID == nil)
    }

    @Test func dateSelectionPreservesTimeAndDurationAndMovesPreviewBetweenDays() throws {
        let appointment = try appointment(hour: 14)
        let calendar = Calendar.autoupdatingCurrent
        let nextDate = appointment.start.date(byAddingDays: 1, using: calendar)
        let model = withDependencies {
            $0.calendar = calendar
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: [.appointment(appointment)])
        model.release()
        let moved = try #require(model.selectDate(nextDate))
        #expect(moved.id == .appointment(appointment.id))
        #expect(calendar.isDate(moved.start, inSameDayAs: nextDate))
        #expect(moved.start.timeOfDay == appointment.start.timeOfDay)
        #expect(moved.durationMinutes == appointment.durationMinutes)
        #expect(model.items([.appointment(appointment)], on: appointment.start).isEmpty)
        #expect(model.items([], on: nextDate).map(\.id) == [.appointment(appointment.id)])
        #expect(model.scale([], on: nextDate).isBreakExpanded)
        #expect(!model.scale([], on: appointment.start).isBreakExpanded)
        #expect(!model.isSaving)
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

    @Test func dateSelectionKeepsClockTimeAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try Date("2026-10-31T16:00:00Z", strategy: .iso8601)
        let nextStart = try Date("2026-11-01T17:00:00Z", strategy: .iso8601)
        let appointment = Appointment(
            patientName: "Patient", start: start, durationMinutes: 45, status: .scheduled)
        let model = withDependencies {
            $0.calendar = calendar
        } operation: {
            TimelineAdjustment()
        }
        model.begin(.appointment(appointment), edge: .move, items: [.appointment(appointment)])
        model.release()
        #expect(model.selectDate(nextStart)?.start == nextStart)
        #expect(model.preview?.durationMinutes == 45)
    }
}
