import Dependencies
import SwiftUI

struct AppointmentDetailsCard: View {
    @Dependency(\.locale) private var locale

    let appointment: Appointment
    let variant: Variant

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(formattedDate)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                    }

                    Text(formattedTimeRange)
                        .font(.title3)
                        .bold()
                }
            }

            if let patient = variant.patient {
                HStack {
                    PatientAvatar(patient: patient)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(patient.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        if let demographics = PatientItemViewMetadata.demographics(for: patient) {
                            Text(demographics)
                                .styleCaption()
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(.rect(cornerRadius: 18))
    }

    private var formattedDate: String {
        appointment.start.formatted(
            .dateTime
                .weekday(.abbreviated)
                .day()
                .month(.abbreviated)
                .year()
                .locale(locale)
        )
    }

    private var formattedTimeRange: String {
        (appointment.start..<appointment.end).formatted(
            .interval
                .hour()
                .minute()
                .locale(locale)
        )
    }

    private var statusColor: Color {
        switch appointment.status {
        case .scheduled:
            .green
        case .draft:
            .accentColor
        case .completed, .cancelled:
            // TODO: Define completed and cancelled status presentation with those features.
            .secondary
        }
    }

    enum Variant: Sendable {
        case standard(patient: Patient)
        case patientTimeline

        fileprivate var patient: Patient? {
            switch self {
            case .standard(let patient):
                patient
            case .patientTimeline:
                nil
            }
        }
    }
}

#Preview("Standard") {
    withDependencies {
        $0.date.now = AppointmentDetailsCard.previewAppointment.start
        $0.locale = Locale(identifier: "en_IN")
    } operation: {
        AppointmentDetailsCard(
            appointment: AppointmentDetailsCard.previewAppointment,
            variant: .standard(patient: AppointmentDetailsCard.previewPatient)
        )
        .padding()
        .background(Color("AppBackground"))
    }
}

#Preview("Patient timeline") {
    withDependencies {
        $0.date.now = AppointmentDetailsCard.previewAppointment.start
        $0.locale = Locale(identifier: "en_IN")
    } operation: {
        AppointmentDetailsCard(
            appointment: AppointmentDetailsCard.previewAppointment,
            variant: .patientTimeline
        )
        .padding()
        .background(Color("AppBackground"))
    }
}

extension AppointmentDetailsCard {
    fileprivate static let previewPatient = Patient(
        name: "Aarav Mehta",
        phone: "+91 98201 44532",
        dob: Date(timeIntervalSinceReferenceDate: -410_313_600),
        gender: .male
    )

    fileprivate static let previewAppointment = Appointment(
        patientName: previewPatient.displayName,
        start: Date(timeIntervalSinceReferenceDate: 798_208_200),
        durationMinutes: 30,
        status: .scheduled
    )
}
