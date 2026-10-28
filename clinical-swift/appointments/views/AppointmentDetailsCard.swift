import ClinicalModels
import Dependencies
import SwiftUI

struct AppointmentDetailsCard: View {
    let appointment: Appointment
    let variant: Variant

    var body: some View {
        switch variant {
        case .standard(let patient, let onSelectPatient):
            VStack(alignment: .leading, spacing: 12) {
                AppointmentDetailsSummary(appointment: appointment)

                Divider()

                PatientSummaryView(
                    patient: patient,
                    onSelect: onSelectPatient
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.surface)
            .clipShape(.rect(cornerRadius: 32))

        case .patientTimeline(let onSelectAppointment):
            Button {
                onSelectAppointment()
            } label: {
                AppointmentDetailsSummary(appointment: appointment)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surface)
                    .clipShape(.rect(cornerRadius: 32))
            }
            .buttonStyle(.plain)
        }
    }

    typealias Action = @MainActor @Sendable () -> Void

    enum Variant: Sendable {
        case standard(patient: Patient, onSelectPatient: Action)
        case patientTimeline(onSelectAppointment: Action)
    }
}

struct AppointmentDetailsSummary: View {
    @Environment(\.appPalette) private var palette
    @Dependency(\.locale) private var locale

    let appointment: Appointment

    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: statusPresentation.systemImage)
                .font(.system(size: 32))
                .frame(width: 32, height: 32)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.1))
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDate)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(AppColor.secondaryText)

                    Spacer()
                }

                Text(formattedTimeRange)
                    .font(.title3)
                    .bold()
                    .foregroundStyle(timeColor)
            }
        }
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

    private var statusPresentation: AppointmentStatusPresentation {
        AppointmentStatusPresentation(status: appointment.status)
    }

    private var statusColor: Color {
        switch statusPresentation.treatment {
        case .active:
            palette[.success]
        case .accent:
            palette[.accent]
        case .muted:
            palette[.secondaryText]
        }
    }

    private var timeColor: Color {
        switch statusPresentation.treatment {
        case .active, .accent:
            palette[.text]
        case .muted:
            palette[.secondaryText]
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
            variant: .standard(
                patient: AppointmentDetailsCard.previewPatient,
                onSelectPatient: {}
            )
        )
        .padding()
        .background(AppColor.canvas)
    }
}

#Preview("Patient timeline") {
    withDependencies {
        $0.date.now = AppointmentDetailsCard.previewAppointment.start
        $0.locale = Locale(identifier: "en_IN")
    } operation: {
        AppointmentDetailsCard(
            appointment: AppointmentDetailsCard.previewAppointment,
            variant: .patientTimeline(onSelectAppointment: {})
        )
        .padding()
        .background(AppColor.canvas)
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
