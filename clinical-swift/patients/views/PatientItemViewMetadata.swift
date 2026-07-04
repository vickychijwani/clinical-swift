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
        @Dependency(\.calendar) var calendar
        @Dependency(\.locale) var locale

        let patient = item.patient
        var parts: [String] = []

        if let demographics = demographics(
            for: patient,
            referenceDate: referenceDate,
            calendar: calendar
        ) {
            parts.append(demographics)
        }

        if patient.isUnknown, let phone = PhoneNumber.formattedForDisplay(patient.phone) {
            parts.append(phone)
        }

        if let nextAppointmentDate = item.nextAppointmentDate {
            parts.append(
                "Next \(formattedAppointmentDate(nextAppointmentDate, locale: locale))"
            )
        } else if patient.isUnknown {
            parts.append(
                "Created \(formattedCreatedDate(patient.createdDate, locale: locale))"
            )
        }

        return PatientItemViewMetadata(parts: parts)
    }

    static func demographics(for patient: Patient) -> String? {
        @Dependency(\.date.now) var referenceDate
        @Dependency(\.calendar) var calendar

        return demographics(
            for: patient,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private static func demographics(
        for patient: Patient,
        referenceDate: Date,
        calendar: Calendar
    ) -> String? {
        var parts: [String] = []

        if let age = patient.age(on: referenceDate, calendar: calendar) {
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

    private static func formattedAppointmentDate(_ date: Date, locale: Locale)
        -> String
    {
        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .locale(locale)
        )
    }

    private static func formattedCreatedDate(_ date: Date, locale: Locale)
        -> String
    {
        date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .locale(locale)
        )
    }
}
