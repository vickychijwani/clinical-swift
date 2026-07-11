import Dependencies
import Foundation
import MessageUI
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentMessageModelTests {
    @Test func sendCopiesBeforeOpeningSMSDraft() throws {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            #expect(model.hasValidRecipientPhone)
            #expect(model.recipientLabel == "+91 98201 44532")
            #expect(model.recipientSystemImage == "phone")
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
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            #expect(model.hasValidRecipientPhone)
            model.startSend()
            let request = try #require(model.finishSMS(with: .sent))
            let didOpenWhatsApp = await model.openWhatsApp(request)

            #expect(didOpenWhatsApp)
            #expect(recorder.openedWhatsApp == [request])
            #expect(model.errorMessage == nil)
        }
    }

    @Test func selectedContactStartsMessageAndSavesPatientConcurrently() async throws {
        let recorder = MessagingRecorder(canSendText: true)
        let database = try testDatabase()
        let details = appointmentDetails(phone: "+91 98201 44532")
        try await database.write { db in
            try PatientRecord.insert { PatientRecord(details.patient) }
                .execute(db)
        }

        await withDependencies {
            $0.appointmentMessagingClient = recorder.client
            $0.defaultDatabase = database
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.selectRecipient(phone: "98765 43210", name: "Nisha Shah")
            #expect(model.willSaveRecipientPhone)
            model.startSend()

            #expect(model.recipientName == "Nisha Shah")
            #expect(model.smsDraft?.recipient == "+919876543210")
            #expect(model.smsDraft?.phoneDigits == "919876543210")

            await model.waitForRecipientPhoneSave()
            #expect(!model.willSaveRecipientPhone)
        }

        let savedPhone = try await database.read { db in
            try PatientRecord.find(details.patient.id).fetchOne(db)?.phone
        }
        #expect(savedPhone == "+919876543210")
    }

    @Test func equivalentSelectedPhoneIsNotMarkedForSaving() {
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.selectRecipient(phone: "98201 44532", name: "Aarav Mobile")

            #expect(!model.willSaveRecipientPhone)
        }
    }

    @Test func failedPatientSaveStillStartsMessageWorkflow() async throws {
        let recorder = MessagingRecorder(canSendText: true)
        let database = try testDatabase()
        let details = appointmentDetails(phone: "+91 98201 44532")

        await withDependencies {
            $0.appointmentMessagingClient = recorder.client
            $0.defaultDatabase = database
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            model.selectRecipient(phone: "98765 43210", name: "Nisha Shah")
            model.startSend()

            #expect(recorder.copiedMessages == [model.message])
            #expect(model.smsDraft?.recipient == "+919876543210")
            #expect(model.smsDraft?.phoneDigits == "919876543210")

            await model.waitForRecipientPhoneSave()
            #expect(model.patientSaveErrorMessage == "This patient can no longer be edited.")
        }
    }

    @Test func loadsInitialRecipientNameFromContacts() async {
        let details = appointmentDetails(phone: "+91 98201 44532")

        await withDependencies {
            $0.appointmentContactClient = AppointmentContactClient { phone in
                #expect(phone == "+919820144532")
                return "Aarav Mobile"
            }
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            await model.loadRecipientName()

            #expect(model.recipientName == "Aarav Mobile")
            #expect(model.recipientLabel == "Aarav Mobile")
            #expect(model.recipientSystemImage == "person")
        }
    }

    @Test func cancelledSMSDoesNotOpenWhatsApp() {
        let recorder = MessagingRecorder(canSendText: true)
        let details = appointmentDetails(phone: "+91 98201 44532")

        withDependencies {
            $0.appointmentMessagingClient = recorder.client
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
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
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
        } operation: {
            let model = AppointmentMessageModel(details: details, includesLocation: false)
            #expect(!model.hasValidRecipientPhone)
            #expect(model.recipientLabel == "Choose contact")
            #expect(model.recipientSystemImage == "person")
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
            $0.calendar = fixedCalendar
            $0.date.now = fixedNow
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

    private var fixedNow: Date {
        Date(timeIntervalSinceReferenceDate: 0)
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    private func testDatabase() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: configuration)
        try migrateDatabase(database)
        return database
    }
}

extension AppointmentMessageModel {
    internal func waitForRecipientPhoneSave() async {
        await recipientPhoneSaveTask?.value
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
