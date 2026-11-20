import ClinicalModels
import Dependencies
import Foundation
import Testing

@testable import clinical_swift

struct PatientItemViewMetadataTests {
    @Test func buildsNamedPatientItemViewMetadataWithoutCreatedDateFallback() throws {
        let calendar = ClinicDate.calendar
        let dob = try #require(calendar.date(1990, 6, 10))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let referenceDate = try #require(calendar.date(2026, 6, 27))
        let patient = Patient(
            name: "Aarav Mehta",
            dob: dob,
            gender: .male,
            createdDate: createdDate
        )

        let (metadata, demographics) = withDependencies {
            $0.date.now = referenceDate
        } operation: {
            (
                PatientItemViewMetadata.metadata(
                    for: PatientDetails(patient: patient, nextAppointmentDate: nil)
                ),
                PatientItemViewMetadata.demographics(for: patient)
            )
        }
        let expectedAge = try #require(patient.age(on: referenceDate, calendar: calendar))

        #expect(metadata.parts == ["\(expectedAge)y/M"])
        #expect(metadata.subtitle == "\(expectedAge)y/M")
        #expect(demographics == "\(expectedAge)y/M")
    }

    @Test func unknownPatientUsesCreatedDateWhenNextAppointmentIsMissing() throws {
        let calendar = ClinicDate.calendar
        let dob = try #require(calendar.date(1990, 6, 10))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let referenceDate = try #require(calendar.date(2026, 6, 27))
        let patient = Patient(
            name: nil,
            phone: "+91 98201 44532",
            dob: dob,
            gender: .female,
            createdDate: createdDate
        )

        let metadata = withDependencies {
            $0.date.now = referenceDate
        } operation: {
            PatientItemViewMetadata.metadata(
                for: PatientDetails(patient: patient, nextAppointmentDate: nil)
            )
        }
        let expectedAge = try #require(patient.age(on: referenceDate, calendar: calendar))

        #expect(metadata.parts.count == 3)
        #expect(metadata.parts[0] == "\(expectedAge)y/F")
        #expect(metadata.parts[1] == "+91 98201 44532")
        #expect(metadata.parts[2].hasPrefix("Created"))
    }

    @Test func nextAppointmentTakesPriorityOverUnknownCreatedDate() throws {
        let calendar = ClinicDate.calendar
        let nextAppointment = try #require(calendar.date(2026, 6, 11, hour: 18))
        let createdDate = try #require(calendar.date(2026, 5, 28))
        let referenceDate = try #require(calendar.date(2026, 6, 27))
        let patient = Patient(
            name: nil,
            phone: "+91 98201 44532",
            createdDate: createdDate
        )

        let metadata = withDependencies {
            $0.date.now = referenceDate
        } operation: {
            PatientItemViewMetadata.metadata(
                for: PatientDetails(patient: patient, nextAppointmentDate: nextAppointment)
            )
        }

        #expect(metadata.parts.count == 2)
        #expect(metadata.parts[0] == "+91 98201 44532")
        #expect(metadata.parts[1].hasPrefix("Next"))
    }
}
