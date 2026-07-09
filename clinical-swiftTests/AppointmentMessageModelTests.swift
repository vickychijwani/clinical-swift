import Dependencies
import Foundation
import MessageUI
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentMessageModelTests {
    @Test func sendCopiesBeforeOpeningSMSDraft() throws {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.startSend()

            #expect(recorder.copiedMessages == [model.message])
            #expect(model.smsDraft?.recipient == "+919820144532")
            #expect(model.smsDraft?.phoneDigits == "919820144532")
            #expect(model.errorMessage == nil)
        }
    }

    @Test func sentSMSReturnsWhatsAppRequestAndOpensWhatsApp() async throws {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: "+91 98201 44532")

        try await withDependencies {
            $0.appointmentMessagingClient = recorder.client
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.startSend()
            let request = try #require(model.finishSMS(with: .sent))
            let didOpenWhatsApp = await model.openWhatsApp(request)

            #expect(didOpenWhatsApp)
            #expect(recorder.openedWhatsApp == [request])
            #expect(model.errorMessage == nil)
        }
    }

    @Test func cancelledSMSDoesNotOpenWhatsApp() {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.startSend()
            let request = model.finishSMS(with: .cancelled)

            #expect(request == nil)
            #expect(recorder.openedWhatsApp.isEmpty)
            #expect(model.errorMessage == nil)
        }
    }

    @Test func missingPhoneCopiesThenFailsAtTapTime() {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: nil)

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.startSend()

            #expect(recorder.copiedMessages == [model.message])
            #expect(model.smsDraft == nil)
            #expect(
                model.errorMessage
                    == "The message was copied, but this patient does not have a usable phone number."
            )
        }
    }

    @Test func unavailableSMSCopiesThenFailsAtTapTime() {
        let recorder = MessagingRecorder(canSendText: false)
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.startSend()

            #expect(recorder.copiedMessages == [model.message])
            #expect(model.smsDraft == nil)
            #expect(
                model.errorMessage
                    == "The message was copied, but SMS is not available on this device.")
        }
    }

    private func appointmentDetails(phone: String?) -> AppointmentDetails {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let patient = Patient(
            name: "Aarav Mehta",
            phone: phone,
            createdDate: start
        )
        return AppointmentDetails(
            appointment: Appointment(
                patientName: patient.displayName,
                start: start,
                durationMinutes: 30,
                status: .scheduled
            ),
            patient: patient
        )
    }
}

@MainActor
private final class MessagingRecorder: @unchecked Sendable {
    let canSendTextValue: Bool
    var copiedMessages: [String] = []
    var openedWhatsApp: [AppointmentWhatsAppRequest] = []

    init(canSendText: Bool) {
        canSendTextValue = canSendText
    }

    var client: AppointmentMessagingClient {
        AppointmentMessagingClient(
            canSendText: { self.canSendTextValue },
            copy: { message in
                self.copiedMessages.append(message)
            },
            openWhatsApp: { phoneDigits, message in
                self.openedWhatsApp.append(
                    AppointmentWhatsAppRequest(phoneDigits: phoneDigits, message: message)
                )
                return true
            }
        )
    }
}
