import ClinicalModels
import ClinicalPersistence
import CoreGraphics
import Dependencies
import Foundation
import SQLiteData
import Synchronization
import Testing

@testable import clinical_swift

@MainActor
struct ClinicDateAppTests {
    @Test func travelAbroadUsesClinicDayAndISTFormattingAcrossScheduleWidgetAndMessages()
        async throws
    {
        // 2026-04-15 10:00 IST is 2026-04-14 21:30 PDT in America/Los_Angeles.
        let appointmentStart = try Date("2026-04-15T04:30:00Z", strategy: .iso8601)
        let clinicMidnight = try Date("2026-04-14T18:30:00Z", strategy: .iso8601)
        let nextClinicMidnight = try Date("2026-04-15T18:30:00Z", strategy: .iso8601)
        let dob = try Date("2000-04-14T18:30:00Z", strategy: .iso8601)  // 2000-04-15 00:00 IST

        let database = try testDatabase()
        let patient = Patient(
            name: "Anjali Desai",
            phone: "+919820144532",
            dob: dob,
            gender: .female,
            createdDate: appointmentStart
        )
        let appointment = Appointment(
            patientName: patient.displayName,
            start: appointmentStart,
            durationMinutes: 30,
            status: .scheduled
        )
        let details = AppointmentDetails(appointment: appointment, patient: patient)

        try await database.write { db in
            try PatientRecord.insert { PatientRecord(patient, now: appointmentStart) }.execute(db)
            let record = try AppointmentRecord.persisted(
                id: appointment.id,
                patientID: patient.id,
                start: appointment.start,
                durationMinutes: appointment.durationMinutes,
                status: .scheduled,
                createdAt: appointmentStart,
                updatedAt: appointmentStart
            )
            try AppointmentRecord.insert { record }.execute(db)
        }

        // ScheduleModel loads and filters by IST clinic day.
        try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = appointmentStart
        } operation: {
            let model = ScheduleModel()
            try await model.loadVisibleDays(centeredOn: clinicMidnight, dayRadius: 1)
            #expect(model.appointments(for: clinicMidnight).map(\.id) == [appointment.id])
            #expect(
                model.appointments(for: clinicMidnight.addingTimeInterval(-1)).isEmpty
            )

            // Timeline layout places 10:00 IST at 10:00 on the clinic scale, not 21:30 PDT.
            #expect(appointmentStart.timeOfDay == TimeOfDay(10, 0))
            let scale = TimelineScale(items: [.appointment(appointment)])
            let layout = try #require(
                TimelineLayoutEngine(availableWidth: 360, scale: scale)
                    .layout(items: [.appointment(appointment)]).first
            )
            #expect(
                layout.rect.minY
                    == scale.yOffset(for: TimeOfDay(10, 0)) + Timeline.metrics.verticalCardMargin
            )

            // Card and TimeOfDay formatting stay in IST + en_IN.
            let cardTime = ScheduleCardStyle.formattedTime(appointmentStart, compact: false)
                .replacingOccurrences(of: "\u{202f}", with: " ")
            #expect(cardTime == "10:00 AM")
            #expect(ScheduleCardStyle.formattedTime(appointmentStart, compact: true) == "10:00")
            let fullTime = TimeOfDay(10, 0).formatted(.full)
                .replacingOccurrences(of: "\u{202f}", with: " ")
            #expect(fullTime == "10:00 AM")

            // Patient metadata computes IST age (26 on Apr 15 IST) and IST appointment date.
            let metadata = PatientItemViewMetadata.metadata(
                for: PatientDetails(patient: patient, nextAppointmentDate: appointmentStart)
            )
            #expect(metadata.parts == ["26y/F", "Next Wed, 15 Apr"])

            // Appointment message uses IST date and time.
            let messageModel = AppointmentMessageModel(details: details, includesLocation: false)
            #expect(messageModel.message.contains("for today at 10:00 AM"))

            // Earlier clinic day formats as "on Wed, 15 Apr" in en_IN.
            let previousDayMessage = withDependencies {
                $0.date.now = clinicMidnight.addingTimeInterval(-60)
            } operation: {
                AppointmentMessageModel(details: details, includesLocation: false).message
            }
            #expect(previousDayMessage.contains("on Wed, 15 Apr at 10:00 AM"))
        }

        // Widget repository groups and refreshes by IST midnight.
        let repository = WidgetScheduleRepository(databaseURL: URL(filePath: "/unused"))
        let morningSnapshot = try repository.snapshot(
            in: database,
            at: appointmentStart.addingTimeInterval(-60)
        )
        #expect(morningSnapshot.sections.first?.date == clinicMidnight)
        #expect(morningSnapshot.sections.first?.items.map(\.id) == [.appointment(appointment.id)])
        #expect(
            morningSnapshot.nextRefreshDate(using: ClinicDate.calendar)
                == appointment.end(using: ClinicDate.calendar)
        )

        let eveningSnapshot = try repository.snapshot(
            in: database,
            at: appointmentStart.addingTimeInterval(60 * 60)
        )
        #expect(eveningSnapshot.sections.first?.items.isEmpty == true)
        #expect(eveningSnapshot.nextRefreshDate(using: ClinicDate.calendar) == nextClinicMidnight)
    }

    @Test func clinicDayRolloverUpdatesAcrossMidnightAndSkipsDuplicateDays() async throws {
        let day1 = try Date("2026-04-14T18:30:00Z", strategy: .iso8601)  // 2026-04-15 00:00 IST
        let day2 = try Date("2026-04-15T18:30:00Z", strategy: .iso8601)  // 2026-04-16 00:00 IST
        let day3 = try Date("2026-04-16T18:30:00Z", strategy: .iso8601)  // 2026-04-17 00:00 IST

        let currentDate = Mutex(try Date("2026-04-15T18:29:00Z", strategy: .iso8601))
        let clock = TestClock()
        var emittedDays: [Date] = []

        let task = withDependencies {
            $0.date = DateGenerator { currentDate.withLock { $0 } }
            $0.continuousClock = clock
        } operation: {
            Task { @MainActor in
                await followClinicDays { day in
                    emittedDays.append(day)
                }
            }
        }

        await Task.yield()
        #expect(emittedDays == [day1])

        // Wake 10 seconds before IST midnight: same clinic day must not emit a duplicate.
        currentDate.withLock { $0 = day2.addingTimeInterval(-10) }
        await clock.advance(by: .seconds(60))
        #expect(emittedDays == [day1])

        // Cross IST midnight into day 2.
        currentDate.withLock { $0 = day2.addingTimeInterval(1) }
        await clock.advance(by: .seconds(10))
        #expect(emittedDays == [day1, day2])

        // Cross IST midnight into day 3.
        currentDate.withLock { $0 = day3.addingTimeInterval(1) }
        await clock.advance(by: .seconds(86_399))
        #expect(emittedDays == [day1, day2, day3])

        // Cancellation exits the rollover loop cleanly.
        task.cancel()
        await task.value
        #expect(emittedDays == [day1, day2, day3])
    }
}
