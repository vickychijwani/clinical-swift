import ClinicalModels
import ClinicalPersistence
import CoreGraphics
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentCarouselTests {
    @Test func windowIndicesKeepAtMostThreeItems() {
        #expect(AppointmentCarouselMotion.windowIndices(around: 0, count: 0) == 0..<0)
        #expect(AppointmentCarouselMotion.windowIndices(around: 0, count: 1) == 0..<1)
        #expect(AppointmentCarouselMotion.windowIndices(around: 0, count: 5) == 0..<2)
        #expect(AppointmentCarouselMotion.windowIndices(around: 2, count: 5) == 1..<4)
        #expect(AppointmentCarouselMotion.windowIndices(around: 4, count: 5) == 3..<5)
    }

    @Test func dragPositionTracksOneToOneAndAppliesRubberBandAtDayEdges() {
        let step: CGFloat = 350
        #expect(
            AppointmentCarouselMotion.dragPosition(
                anchorIndex: 1, translation: -120, count: 3, step: step)
                == step + 120
        )

        let leadingEdge = AppointmentCarouselMotion.dragPosition(
            anchorIndex: 0, translation: 140, count: 3, step: step)
        #expect(leadingEdge < 0)
        #expect(leadingEdge > -step * AppointmentCarouselMotion.boundaryLimitFraction)

        let trailingEdge = AppointmentCarouselMotion.dragPosition(
            anchorIndex: 2, translation: -140, count: 3, step: step)
        #expect(trailingEdge > 2 * step)
        #expect(trailingEdge < 2 * step + step * AppointmentCarouselMotion.boundaryLimitFraction)

        let soloLeft = AppointmentCarouselMotion.dragPosition(
            anchorIndex: 0, translation: -100, count: 1, step: step)
        #expect(soloLeft > 0)
        #expect(soloLeft < step * AppointmentCarouselMotion.boundaryLimitFraction)
    }

    @Test func targetIndexCommitsByDistanceOrFlickAndNeverCrossesBounds() {
        let step: CGFloat = 350
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 1, count: 3, step: step,
                translation: -110, predictedTranslation: -110) == 2
        )
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 1, count: 3, step: step,
                translation: -40, predictedTranslation: -180) == 2
        )
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 1, count: 3, step: step,
                translation: -40, predictedTranslation: -60) == 1
        )
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 1, count: 3, step: step,
                translation: 120, predictedTranslation: 120) == 0
        )
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 0, count: 3, step: step,
                translation: 200, predictedTranslation: 300) == 0
        )
        #expect(
            AppointmentCarouselMotion.targetIndex(
                currentIndex: 2, count: 3, step: step,
                translation: -200, predictedTranslation: -300) == 2
        )
    }

    @Test func carouselOrderFiltersStatusesAndMatchesTimelineLeftToRightLayout() throws {
        let dayStart = try Date("2026-10-30T03:30:00Z", strategy: .iso8601)  // 09:00 IST
        let tenAM = dayStart.addingTimeInterval(3600)
        let noon = dayStart.addingTimeInterval(3 * 3600)

        let early = makeDetails(name: "Early", start: dayStart, duration: 30, status: .completed)
        let tieShort = makeDetails(name: "Short", start: tenAM, duration: 15, status: .scheduled)
        let tieLong = makeDetails(name: "Long", start: tenAM, duration: 60, status: .scheduled)
        let tieMedium = makeDetails(name: "Medium", start: tenAM, duration: 45, status: .completed)
        let cancelled = makeDetails(
            name: "Cancelled", start: tenAM, duration: 30, status: .cancelled)
        let draft = makeDetails(name: "Draft", start: noon, duration: 30, status: .draft)
        let late = makeDetails(name: "Late", start: noon, duration: 30, status: .scheduled)
        let block = UnavailableTime(
            label: "Break", start: tenAM, durationMinutes: 30)

        let overlap = ScheduleCardTuning().overlap
        let ordered = AppointmentCarouselOrder.orderedAppointments(
            appointments: [late, draft, cancelled, tieShort, tieMedium, early, tieLong],
            unavailableTimes: [block],
            availableWidth: 402,
            overlap: overlap
        )

        #expect(ordered.map(\.id).contains(cancelled.id) == false)
        #expect(ordered.map(\.id).contains(draft.id) == false)
        #expect(ordered.first?.id == early.id)
        #expect(ordered.last?.id == late.id)

        // Verify the 10:00 AM ties match the exact horizontal order produced by TimelineLayoutEngine.
        let timelineItems =
            ordered.map { TimelineItem.appointment($0.appointment) }
            + [TimelineItem.unavailableTime(block)]
        let layouts = TimelineLayoutEngine(
            availableWidth: 402,
            scale: TimelineScale(items: timelineItems),
            overlap: overlap,
            assertOnFallback: false
        ).layout(items: timelineItems)
        let tenAMExpected = layouts.compactMap { info -> (Appointment.ID, CGFloat)? in
            guard case .appointment(let appointment) = info.item,
                appointment.start == tenAM
            else { return nil }
            return (appointment.id, info.rect.minX)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)

        let tenAMOrdered = ordered.filter { $0.appointment.start == tenAM }.map(\.id)
        #expect(tenAMOrdered == tenAMExpected)
    }

    @Test func routerSelectCarouselAppointmentUpdatesRootInPlaceAndDiscardsDraft() throws {
        let day = try Date("2026-10-30T04:30:00Z", strategy: .iso8601)
        let first = makeDetails(name: "First", start: day, duration: 30, status: .scheduled)
        let second = makeDetails(
            name: "Second", start: day.addingTimeInterval(3600), duration: 30, status: .completed)

        let router = Router(selectedScheduleDate: day)
        router.presentDetails(.appointment(first.id))
        let presentation = try #require(router.detailsPresentation)
        let originalSessionID = presentation.id
        let originalVisitID = presentation.visitID

        // Back-kept completion draft should be discarded silently on carousel swipe.
        router.beginAppointmentCompletion(
            first, visitID: first.id, presentationID: presentation.id)
        presentation.completionDrafts[first.id]?.setAmountText("500")
        router.setDetailsPath([], presentationID: presentation.id)
        #expect(presentation.hasUnsavedCompletion)

        router.selectCarouselAppointment(second.id, presentationID: presentation.id)
        #expect(presentation.id == originalSessionID)
        #expect(presentation.visitID == originalVisitID)
        #expect(presentation.root == .appointment(second.id))
        #expect(presentation.completionDrafts.isEmpty)
        #expect(ScheduleView.selectedAppointmentID(for: router, hasEditor: false) == second.id)

        // Pushing a child view blocks carousel switches.
        router.pushDetails(.patient(second.patient.id))
        router.selectCarouselAppointment(first.id, presentationID: presentation.id)
        #expect(presentation.root == .appointment(second.id))

        // Wrong presentation ID is ignored.
        router.setDetailsPath([], presentationID: presentation.id)
        router.selectCarouselAppointment(first.id, presentationID: UUID())
        #expect(presentation.root == .appointment(second.id))
    }

    @Test func dayCarouselModelLoadsScheduledAndCompletedOnlyForDay() async throws {
        let database = try testDatabase()
        let morning = try Date("2026-10-30T04:30:00Z", strategy: .iso8601)  // 10:00 IST
        let evening = try Date("2026-10-30T14:30:00Z", strategy: .iso8601)  // 20:00 IST
        let nextDay = try Date("2026-10-31T04:30:00Z", strategy: .iso8601)
        let patient = Patient(name: "Asha Rao")

        let scheduled = Appointment(
            patientName: patient.displayName, start: morning, durationMinutes: 30,
            status: .scheduled)
        let completed = Appointment(
            patientName: patient.displayName, start: evening, durationMinutes: 30,
            status: .completed)
        let cancelled = Appointment(
            patientName: patient.displayName, start: morning.addingTimeInterval(1800),
            durationMinutes: 30, status: .cancelled)
        let tomorrow = Appointment(
            patientName: patient.displayName, start: nextDay, durationMinutes: 30,
            status: .scheduled)

        try await database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patient.id, name: patient.name, phone: nil, dob: nil, gender: nil,
                    createdAt: morning, updatedAt: morning)
            }.execute(db)
            for item in [scheduled, completed, cancelled, tomorrow] {
                let record = try AppointmentRecord.persisted(
                    id: item.id, patientID: patient.id, start: item.start,
                    durationMinutes: item.durationMinutes, status: item.status,
                    createdAt: morning, updatedAt: morning)
                try AppointmentRecord.insert { record }.execute(db)
            }
        }

        await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = morning
        } operation: {
            let model = AppointmentDayCarouselModel(
                initialAppointmentID: scheduled.id,
                initialScheduleDate: morning
            )
            await model.loadInitial()
            let ordered = model.orderedAppointments(
                availableWidth: 402, overlap: ScheduleCardTuning().overlap)
            #expect(ordered.map(\.id) == [scheduled.id, completed.id])
            #expect(model.activeDetails(in: ordered)?.id == scheduled.id)

            model.select(appointmentID: completed.id)
            #expect(model.activeDetails(in: ordered)?.id == completed.id)
        }
    }

    @Test func dayCarouselModelStatusUpdateRefreshesOnConflictAndClearsErrorOnSelect() async throws
    {
        let database = try testDatabase()
        let morning = try Date("2026-10-30T04:30:00Z", strategy: .iso8601)  // 10:00 IST
        let updatedAt = try Date("2026-10-30T05:00:00Z", strategy: .iso8601)
        let patient = Patient(name: "Asha Rao")

        let first = Appointment(
            patientName: patient.displayName, start: morning, durationMinutes: 30,
            status: .scheduled)
        let second = Appointment(
            patientName: patient.displayName, start: morning.addingTimeInterval(3600),
            durationMinutes: 30, status: .scheduled)

        try await database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patient.id, name: patient.name, phone: nil, dob: nil, gender: nil,
                    createdAt: morning, updatedAt: morning)
            }.execute(db)
            for item in [first, second] {
                let record = try AppointmentRecord.persisted(
                    id: item.id, patientID: patient.id, start: item.start,
                    durationMinutes: item.durationMinutes, status: item.status,
                    createdAt: morning, updatedAt: morning)
                try AppointmentRecord.insert { record }.execute(db)
            }
        }

        try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = updatedAt
        } operation: {
            let model = AppointmentDayCarouselModel(
                initialAppointmentID: first.id,
                initialScheduleDate: morning
            )
            await model.loadInitial()

            _ = try await database.updateAppointmentStatus(
                id: first.id, to: .completed, at: morning.addingTimeInterval(600))

            let conflictResult = await model.updateStatus(for: first.id, to: .cancelled)
            #expect(!conflictResult)
            #expect(model.errorMessage == "This appointment was already completed.")

            let refreshed = model.orderedAppointments(
                availableWidth: 402, overlap: ScheduleCardTuning().overlap)
            #expect(model.activeDetails(in: refreshed)?.appointment.status == .completed)

            model.select(appointmentID: second.id)
            #expect(model.errorMessage == nil)

            let cancelResult = await model.updateStatus(for: second.id, to: .cancelled)
            #expect(cancelResult)
            #expect(model.errorMessage == nil)
        }

        let secondRecord = try await database.read { db in
            try AppointmentRecord.find(second.id).fetchOne(db)
        }
        #expect(secondRecord?.status == Appointment.Status.cancelled.rawValue)
        #expect(secondRecord?.updatedAt == updatedAt)
    }

    private func makeDetails(
        name: String,
        start: Date,
        duration: Int,
        status: Appointment.Status
    ) -> AppointmentDetails {
        let patient = Patient(name: name)
        let appointment = Appointment(
            patientName: patient.displayName,
            start: start,
            durationMinutes: duration,
            status: status
        )
        return AppointmentDetails(appointment: appointment, patient: patient)
    }
}
