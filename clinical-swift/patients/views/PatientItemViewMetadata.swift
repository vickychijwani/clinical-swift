import ClinicalModels
import Dependencies
import Foundation

struct PatientItemViewMetadata: Equatable {
    let parts: [String]

    var subtitle: String? {
        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " · ")
    }

    static func metadata(for item: PatientDetails) -> PatientItemViewMetadata {
        @Dependency(\.date.now) var referenceDate

        let patient = item.patient
        var parts: [String] = []

        if let demographics = demographics(
            for: patient,
            referenceDate: referenceDate
        ) {
            parts.append(demographics)
        }

        if patient.isUnknown, let phone = PhoneNumber.formattedForDisplay(patient.phone) {
            parts.append(phone)
        }

        if let nextAppointmentDate = item.nextAppointmentDate {
            parts.append(
                "Next \(formattedAppointmentDate(nextAppointmentDate))"
            )
        } else if patient.isUnknown {
            parts.append(
                "Created \(formattedCreatedDate(patient.createdDate))"
            )
        }

        return PatientItemViewMetadata(parts: parts)
    }

    static func demographics(for patient: Patient) -> String? {
        @Dependency(\.date.now) var referenceDate

        return demographics(
            for: patient,
            referenceDate: referenceDate
        )
    }

    private static func demographics(
        for patient: Patient,
        referenceDate: Date
    ) -> String? {
        var parts: [String] = []

        if let age = patient.age(on: referenceDate, calendar: ClinicDate.calendar) {
            parts.append("\(age)y")
        }

        if let gender = patient.gender {
            parts.append(gender.displayName)
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: "/")
    }

    private static func formattedAppointmentDate(_ date: Date)
        -> String
    {
        date.formatted(
            ClinicDate.formatStyle
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
        )
    }

    private static func formattedCreatedDate(_ date: Date)
        -> String
    {
        date.formatted(
            ClinicDate.formatStyle
                .day()
                .month(.abbreviated)
        )
    }
}
