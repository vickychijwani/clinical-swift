import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

struct ClinicDateTests {
    @Test func clinicDatePinsAsiaKolkataAndEnIN() throws {
        #expect(ClinicDate.timeZone.identifier == "Asia/Kolkata")
        #expect(ClinicDate.locale.identifier == "en_IN")
        #expect(ClinicDate.calendar.identifier == .gregorian)
        #expect(ClinicDate.calendar.timeZone.identifier == "Asia/Kolkata")
        #expect(ClinicDate.calendar.locale?.identifier == "en_IN")

        // 2026-04-15 10:00 IST is 2026-04-14 21:30 PDT in America/Los_Angeles.
        let morningIST = try Date("2026-04-15T04:30:00Z", strategy: .iso8601)
        let midnightIST = try Date("2026-04-14T18:30:00Z", strategy: .iso8601)
        let nextMidnightIST = try Date("2026-04-15T18:30:00Z", strategy: .iso8601)

        #expect(ClinicDate.day(morningIST) == midnightIST)
        #expect(ClinicDate.nextDay(morningIST) == nextMidnightIST)
        #expect(morningIST.isSameDayAs(midnightIST))
        #expect(!morningIST.isSameDayAs(midnightIST.addingTimeInterval(-1)))

        withDependencies {
            $0.date.now = morningIST
        } operation: {
            #expect(ClinicDate.today == midnightIST)
        }
    }

    @Test func clinicDateFormatStylesUseISTAndEnIN() throws {
        // 2026-04-15 10:00 IST to 10:30 IST (previous calendar day in America/Los_Angeles).
        let start = try Date("2026-04-15T04:30:00Z", strategy: .iso8601)
        let end = try Date("2026-04-15T05:00:00Z", strategy: .iso8601)

        let formattedDate = start.formatted(
            ClinicDate.formatStyle.weekday(.abbreviated).day().month(.abbreviated).year()
        )
        #expect(formattedDate == "Wed, 15 Apr 2026")

        let formattedTime = start.formatted(ClinicDate.formatStyle.hour().minute())
        #expect(formattedTime.contains("10:00"))
        #expect(formattedTime.localizedCaseInsensitiveContains("am"))

        let formattedRange = (start..<end).formatted(ClinicDate.intervalFormatStyle.hour().minute())
        #expect(formattedRange.contains("10:00"))
        #expect(formattedRange.contains("10:30"))
        #expect(formattedRange.localizedCaseInsensitiveContains("am"))
    }

    @Test func scheduleAndUnavailableTimeQueriesUseClinicDaysAbroad() throws {
        let database = try testDatabase()
        let patientID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let appointmentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000102"))
        let blockID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000103"))

        // 2026-04-15 00:30 IST (2026-04-14 19:00 UTC / 12:00 PDT) and 10:00 IST (04:30 UTC / 21:30 PDT Apr 14).
        let appointmentStart = try Date("2026-04-15T04:30:00Z", strategy: .iso8601)
        let blockStart = try Date("2026-04-14T19:00:00Z", strategy: .iso8601)
        let queryDate = try Date("2026-04-15T12:00:00Z", strategy: .iso8601)  // 17:30 IST on Apr 15
        let previousClinicDay = try Date("2026-04-14T12:00:00Z", strategy: .iso8601)  // 17:30 IST on Apr 14

        try database.write { db in
            try PatientRecord.insert {
                PatientRecord(
                    id: patientID, name: "Anjali Desai", phone: nil, dob: nil,
                    gender: Gender.female.storageValue,
                    createdAt: appointmentStart, updatedAt: appointmentStart)
            }.execute(db)
            let appointment = try AppointmentRecord.persisted(
                id: appointmentID, patientID: patientID, start: appointmentStart,
                durationMinutes: 30, status: .scheduled,
                createdAt: appointmentStart, updatedAt: appointmentStart)
            try AppointmentRecord.insert { appointment }.execute(db)
            try UnavailableTimeRecord.insert {
                UnavailableTimeRecord(
                    id: blockID, label: "Morning block", start: blockStart, durationMinutes: 30,
                    createdAt: blockStart, updatedAt: blockStart)
            }.execute(db)
        }

        try database.read { db in
            let april15Schedule = try querySchedule(selectedDate: queryDate).fetchAll(db)
            #expect(april15Schedule.map(\.id) == [appointmentID])

            let april14Schedule = try querySchedule(selectedDate: previousClinicDay).fetchAll(db)
            #expect(april14Schedule.isEmpty)

            let windowRows = try queryScheduleWindow(centeredOn: queryDate, dayRadius: 1)
                .fetchAll(db)
            #expect(windowRows.map(\.id) == [appointmentID])

            // Day centered on Apr 13 with radius 1 covers Apr 12..Apr 14 IST and must exclude Apr 15 00:30 IST.
            let april13 = try Date("2026-04-13T12:00:00Z", strategy: .iso8601)
            let earlierBlocks = try unavailableTimesQuery(centeredOn: april13, dayRadius: 1)
                .fetchAll(db)
            #expect(earlierBlocks.isEmpty)

            let april15Blocks = try unavailableTimesQuery(centeredOn: queryDate, dayRadius: 1)
                .fetchAll(db)
            #expect(april15Blocks.map(\.id) == [blockID])
        }
    }

    @Test func patientAgeUsesClinicDayBoundaries() throws {
        // Born 2000-04-15 00:00 IST (2000-04-14T18:30:00Z).
        let dob = try Date("2000-04-14T18:30:00Z", strategy: .iso8601)
        let patient = Patient(name: "Aarav Mehta", dob: dob)

        // One second before birthday in IST (23:59:59 IST on Apr 14).
        let beforeBirthday = try Date("2026-04-14T18:29:59Z", strategy: .iso8601)
        // Midnight of birthday in IST (00:00:00 IST on Apr 15, still Apr 14 in America/Los_Angeles).
        let onBirthday = try Date("2026-04-14T18:30:00Z", strategy: .iso8601)

        #expect(patient.age(on: beforeBirthday) == 25)
        #expect(patient.age(on: onBirthday) == 26)
    }
}
