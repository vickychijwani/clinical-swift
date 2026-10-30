import ClinicalModels
import ClinicalPersistence
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import clinical_swift

@MainActor
struct AppointmentCompletionTests {
    @Test func parsesExactWholeRupeeValues() {
        for (text, expected) in [
            ("", 0), ("0", 0), ("000", 0), ("500", 500), ("1,000", 1000),
            ("10,000", 10000), ("1,00,000", 100000), (" ₹ 1,00,000 \n", 100000),
            (String(Int.max), Int.max),
        ] {
            #expect(CompletionAmount.parse(text) == expected)
        }
    }
    @Test(arguments: [
        "-500", "500.50", "+500", "abc", "₹", "1,0000", "100,000", "1,,000", "1,00", "1,000,000",
        "9,22,33,72,03,68,54,77,5808", String(Int.max) + "0",
    ])
    func rejectsInvalidAmounts(_ text: String) {
        #expect(CompletionAmount.parse(text) == nil)
        let model = makeModel()
        model.setAmountText(text)
        #expect(!model.canSave)
        #expect(model.buttonTitle == "Complete Appointment")
        #expect(model.buttonSymbol == "checkmark.circle")
    }

    @Test func inputTextIsKeptWithoutRewritingNativeEdits() {
        let model = makeModel()
        for text in [
            "1", "10", "100", "1000", "10000", "100000", "1,00,000", "1,0000", "-500", "500.50", "",
        ] {
            model.setAmountText(text)
            #expect(model.amountText == text)
        }
        model.setAmountText("100000")
        #expect(model.buttonTitle == "₹1,00,000 Paid · Complete Appointment")
    }
    @Test func labelsAndDirtyStateFollowDraftValues() {
        let model = makeModel()
        #expect(model.amountText.isEmpty)
        #expect(model.patientName == "Unknown Patient")
        #expect(model.paymentMethod == nil)
        #expect(!model.hasUnsavedChanges)
        #expect(model.canSave)
        #expect(model.buttonTitle == "No Dues · Complete Appointment")
        model.selectMethod(.card)
        #expect(model.hasUnsavedChanges)
        model.selectMethod(nil)
        #expect(!model.hasUnsavedChanges)
        model.setAmountText("000")
        #expect(model.amount == 0)
        #expect(model.hasUnsavedChanges)
        #expect(model.buttonTitle == "No Dues · Complete Appointment")
        model.setAmountText("1000")
        #expect(model.buttonTitle == "₹1,000 Paid · Complete Appointment")
        #expect(model.buttonSymbol == "indianrupeesign.circle")
        model.setAmountText("")
        #expect(!model.hasUnsavedChanges)
        model.setAmountText("1000")
        model.selectMethod(.card)
        model.setAmountText("")
        #expect(model.hasUnsavedChanges)
        model.selectMethod(nil)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func failureKeepsDraftAndMethodForRetry() async throws {
        let database = try testDatabase()
        await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSinceReferenceDate: 1000)
        } operation: {
            let model = makeModel()
            model.setAmountText("1000")
            model.selectMethod(.upi)
            #expect(await model.save() == false)
            #expect(model.errorMessage == "This appointment is no longer available.")
            #expect(model.amountText == "1000")
            #expect(model.paymentMethod == .upi)
            #expect(model.canSave)
        }
    }

    @Test func invalidDraftCannotCompleteWithoutPayment() async throws {
        let database = try testDatabase()
        await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let model = makeModel()
            model.setAmountText("-500")
            #expect(await model.save() == false)
            #expect(model.errorMessage == nil)
        }
    }

    @Test func backKeepsDraftAtAnyDepthAndNewVisitsStartEmpty() throws {
        let router = makeRouter()
        let details = makeDetails()
        router.presentDetails(.patient(details.patient.id))
        let presentation = try #require(router.detailsPresentation)
        router.pushDetails(.appointment(details.id))
        let visitID = UUID()
        router.beginAppointmentCompletion(
            details, visitID: visitID, presentationID: presentation.id)
        let model = try #require(presentation.completionDrafts[visitID])
        model.setAmountText("1000")
        model.selectMethod(.cash)
        #expect(presentation.path == [.appointment(details.id), .appointmentCompletion(visitID)])
        #expect(presentation.hasUnsavedCompletion)
        router.setDetailsPath([.appointment(details.id)], presentationID: presentation.id)
        router.beginAppointmentCompletion(
            details, visitID: visitID, presentationID: presentation.id)
        #expect(presentation.completionDrafts[visitID] === model)
        #expect(model.amountText == "1000")
        #expect(model.paymentMethod == .cash)
        router.setDetailsPath([], presentationID: presentation.id)
        #expect(presentation.completionDrafts.isEmpty)
        router.pushDetails(.appointment(details.id))
        let newVisit = UUID()
        router.beginAppointmentCompletion(
            details, visitID: newVisit, presentationID: presentation.id)
        #expect(presentation.completionDrafts[newVisit]?.amountText == "")
        #expect(presentation.completionDrafts[newVisit]?.paymentMethod == nil)
    }

    @Test func differentAppointmentsDoNotShareADraftEvenWhenAVisitIDIsReused() throws {
        let router = makeRouter()
        let first = makeDetails()
        let second = makeDetails()
        router.presentDetails(.appointment(first.id))
        let presentation = try #require(router.detailsPresentation)
        let visit = UUID()
        router.beginAppointmentCompletion(first, visitID: visit, presentationID: presentation.id)
        let old = try #require(presentation.completionDrafts[visit])
        old.setAmountText("500")
        old.selectMethod(.upi)
        router.presentDetails(.appointment(second.id))
        router.beginAppointmentCompletion(second, visitID: visit, presentationID: presentation.id)
        let replacement = try #require(presentation.completionDrafts[visit])
        #expect(replacement !== old)
        #expect(replacement.appointmentID == second.id)
        #expect(replacement.patientID == second.patient.id)
        #expect(replacement.amountText.isEmpty)
        #expect(replacement.paymentMethod == nil)
    }

    @Test func lateSaveCannotDismissReusedSessionOrAnotherDestination() throws {
        let router = makeRouter()
        let details = makeDetails()
        router.presentDetails(.appointment(details.id))
        let presentation = try #require(router.detailsPresentation)
        let visit = UUID()
        router.beginAppointmentCompletion(details, visitID: visit, presentationID: presentation.id)
        let oldModel = try #require(presentation.completionDrafts[visit])
        router.setDetailsPath([], presentationID: presentation.id)
        router.finishAppointmentCompletion(oldModel, presentationID: presentation.id)
        #expect(router.detailsPresentation === presentation)
        router.presentDetails(.appointment(details.id))
        #expect(presentation.completionDrafts.isEmpty)
        router.beginAppointmentCompletion(details, visitID: visit, presentationID: presentation.id)
        router.finishAppointmentCompletion(oldModel, presentationID: presentation.id)
        #expect(router.detailsPresentation === presentation)
        let current = try #require(presentation.completionDrafts[visit])
        router.finishAppointmentCompletion(current, presentationID: presentation.id)
        #expect(router.detailsPresentation == nil)
        #expect(router.selectedTab == .schedule)
    }

    @Test func externalReplacementAndDateChangeDiscardDrafts() throws {
        let router = makeRouter()
        let details = makeDetails()
        for useDateChange in [false, true] {
            router.presentDetails(.appointment(details.id))
            let presentation = try #require(router.detailsPresentation)
            let visit = UUID()
            router.beginAppointmentCompletion(
                details, visitID: visit, presentationID: presentation.id)
            let model = try #require(presentation.completionDrafts[visit])
            model.setAmountText("500")
            if useDateChange {
                router.selectScheduleDate(router.selectedScheduleDate.addingTimeInterval(86400))
            } else {
                router.requestScheduleCreation()
            }
            router.finishAppointmentCompletion(model, presentationID: presentation.id)
            #expect(router.detailsPresentation == nil)
        }
    }

    private func makeRouter() -> Router {
        withDependencies {
            $0.calendar = FinancialDate.calendar
        } operation: {
            Router()
        }
    }

    private func makeModel() -> AppointmentCompletionModel {
        AppointmentCompletionModel(id: UUID(), details: makeDetails(), originPath: [])
    }

    private func makeDetails() -> AppointmentDetails {
        let patient = Patient(name: nil)
        return AppointmentDetails(
            appointment: Appointment(
                patientName: patient.displayName, start: .now, durationMinutes: 30,
                status: .scheduled), patient: patient)
    }
}
