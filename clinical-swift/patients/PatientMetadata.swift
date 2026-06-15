import Dependencies
import Foundation

struct PatientMetadata: Equatable {
    let parts: [String]

    var subtitle: String? {
        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " · ")
    }

    static func metadata(for item: PatientListItem) -> PatientMetadata {
        let patient = item.patient
        var parts: [String] = []
        var demographics: [String] = []

        if let age = patient.age(on: .now, calendar: .autoupdatingCurrent) {
            demographics.append("\(age)y")
        }

        if let gender = patient.gender {
            demographics.append(gender.displayName)
        }

        if !demographics.isEmpty {
            parts.append(demographics.joined(separator: "/"))
        }

        if patient.isUnknown, let phone = patient.phone {
            parts.append(phone)
        }

        let locale: Locale = .autoupdatingCurrent
        if let nextAppointmentDate = item.nextAppointmentDate {
            parts.append(
                "Next \(formattedAppointmentDate(nextAppointmentDate, locale: locale))"
            )
        } else if patient.isUnknown {
            parts.append(
                "Created \(formattedCreatedDate(patient.createdDate, locale: locale))"
            )
        }

        return PatientMetadata(parts: parts)
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
