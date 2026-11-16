import Dependencies
import Foundation
import Testing

@testable import clinical_swift

@MainActor
struct TrayTests {
    private nonisolated struct Item: Identifiable, Sendable {
        let id = UUID()
    }

    @Test func reopeningDuringExitWaitsAndRegistersOneNewEntry() {
        let state = TrayState<Item>()
        let item = Item()
        var appeared: [UUID] = []
        state.update(item) { appeared.append($0) }
        let firstSurface = state.surfaceID
        state.finishEntry(firstSurface)
        state.update(nil) { appeared.append($0) }
        state.update(item) { appeared.append($0) }
        #expect(state.phase == .exiting(firstSurface))
        #expect(appeared == [item.id])
        #expect(state.finishExit(firstSurface))
        state.update(item) { appeared.append($0) }
        #expect(state.surfaceID != firstSurface)
        #expect(state.phase == .entering(state.surfaceID))
        state.finishEntry(firstSurface)
        #expect(state.phase == .entering(state.surfaceID))
        state.update(nil) { appeared.append($0) }
        #expect(!state.finishExit(firstSurface))
        #expect(state.item?.id == item.id)
        #expect(appeared == [item.id, item.id])
    }

    @Test func staleDismissActionsCannotCloseANewerStep() {
        var currentID = UUID()
        let origin = currentID
        var dismissed = false
        let action = TrayDismissAction(
            id: origin, isCurrent: { currentID == origin }, dismiss: { dismissed = true })
        currentID = UUID()
        action()
        #expect(!dismissed)
        currentID = origin
        action()
        #expect(dismissed)
    }

    @Test func fittedAndFullSizesUseTheAvailableSpaceAndClampContent() {
        let size = CGSize(width: 402, height: 874)
        let fitted = TrayLayout.resolve(
            sizing: .fitted, size: size, topInset: 62, bottomInset: 34, fittedHeight: 300)
        let fixed = TrayLayout.resolve(
            sizing: .height(300), size: size, topInset: 62, bottomInset: 34)
        #expect(fitted == fixed)
        let full = TrayLayout.resolve(
            sizing: .full, size: size, topInset: 62, bottomInset: 34)
        let overflow = TrayLayout.resolve(
            sizing: .fitted, size: size, topInset: 62, bottomInset: 34, fittedHeight: 2_000)
        #expect(overflow == full)
        #expect(full.topEdge == 62)
    }

    @Test func exitRetainsContentAndOnlyActivatesTheNewestReplacement() throws {
        let router = makeRouter()
        router.presentDetails(.patient(UUID()))
        let original = try #require(router.detailsPresentation)
        let state = TrayState<DetailsPresentation>()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        let surfaceID = state.surfaceID
        #expect(state.phase == .entering(surfaceID))
        router.requestScheduleCreation()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        #expect(state.phase == .exiting(surfaceID))
        #expect(state.item === original)
        state.finishEntry(surfaceID)
        #expect(state.phase == .exiting(surfaceID))
        router.requestPatientCreation()
        #expect(router.activePresentation == nil)
        #expect(!state.finishExit(UUID()))
        #expect(state.item === original)
        if state.finishExit(surfaceID) {
            router.presentationDidDismiss(original.id)
            state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        }
        let editorID = try #require(router.patientEditRequest?.id)
        #expect(state.item == nil)
        if state.finishExit(surfaceID) {
            router.presentationDidDismiss(original.id)
            state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        }
        router.presentationDidDismiss(original.id)
        #expect(router.activePresentation?.id == editorID)
    }

    @Test func replacementDetailsStartsAfterExitAndRejectsOldCallbacks() throws {
        let router = makeRouter()
        router.presentDetails(.patient(UUID()))
        let state = TrayState<DetailsPresentation>()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        let oldID = try #require(state.item?.id)
        let oldSurface = state.surfaceID
        router.dismissDetails()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        router.presentDetails(.appointment(UUID()))
        if state.finishExit(oldSurface) {
            router.presentationDidDismiss(oldID)
            state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        }
        let newID = try #require(state.item?.id)
        #expect(newID != oldID)
        #expect(state.phase == .entering(state.surfaceID))
        state.finishEntry(oldSurface)
        if state.finishExit(oldSurface) {
            router.presentationDidDismiss(oldID)
            state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        }
        router.dismissDetails(presentationID: oldID)
        router.pushDetails(.patient(UUID()), presentationID: oldID, visitID: UUID())
        #expect(router.detailsPresentation?.id == newID)
        #expect(router.detailsPresentation?.path.isEmpty == true)
        state.finishEntry(state.surfaceID)
        #expect(state.phase == .visible(state.surfaceID))
    }

    @Test func sameSessionRootReplacementDoesNotRestartEntry() throws {
        let router = makeRouter()
        router.presentDetails(.patient(UUID()))
        let state = TrayState<DetailsPresentation>()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        let id = try #require(state.item?.id)
        let surfaceID = state.surfaceID
        router.presentDetails(.appointment(UUID()))
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        #expect(state.phase == .entering(surfaceID))
        state.finishEntry(surfaceID)
        router.dismissDetails()
        state.update(router.detailsPresentation, didAppear: router.presentationDidAppear)
        if state.finishExit(surfaceID) { router.presentationDidDismiss(id) }
        #expect(router.activePresentation == nil)
        #expect(state.phase == .hidden)
    }

    @Test func fixedDetentsIncludeScaledSafeAreaSpace() {
        let compact = TrayLayout.resolve(
            sizing: .height(280), size: CGSize(width: 402, height: 874),
            topInset: 62, bottomInset: 34)
        #expect(abs(compact.height - 314) < 0.001)
        #expect(abs(compact.scale - 386.0 / 402) < 0.001)
        let completion = TrayLayout.resolve(
            sizing: .height(400), size: CGSize(width: 402, height: 874),
            topInset: 62, bottomInset: 34)
        #expect(abs(completion.height - 434) < 0.001)
        let keyboard = TrayLayout.resolve(
            sizing: .height(400), size: CGSize(width: 402, height: 874),
            topInset: 62, bottomInset: 34, keyboardHeight: 308)
        #expect(abs(keyboard.height - 742) < 0.001)
        #expect(keyboard.bottomInset == 34)
        let smallPhone = TrayLayout.resolve(
            sizing: .height(400), size: CGSize(width: 375, height: 667),
            topInset: 20, bottomInset: 0, keyboardHeight: 235)
        #expect(smallPhone.scale == 1)
        #expect(smallPhone.bottomMargin == 0)
        #expect(smallPhone.height == 635)
        let shortContainer = TrayLayout.resolve(
            sizing: .height(400), size: CGSize(width: 375, height: 432),
            topInset: 20, bottomInset: 0)
        #expect(shortContainer.scale == 1)
        #expect(shortContainer.bottomMargin == 0)
    }

    @Test(arguments: [TraySize.height(280), .medium, .height(400), .full, .fitted])
    func shortAndKeyboardContainersKeepTheTrayBelowTheTopSafeArea(_ detent: TraySize) {
        for height in [0.0, 80, 320, 550] {
            let layout = TrayLayout.resolve(
                sizing: detent, size: CGSize(width: 375, height: height),
                topInset: 62, bottomInset: 34)
            #expect(layout.height >= 0)
            #expect(layout.height * layout.scale <= max(0, height - 62) + 0.001)
            #expect(layout.bottomInset <= layout.height)
        }
    }

    @Test func widthFollowsTheRenderedTopEdgeWithoutAStep() {
        var previousScale: CGFloat = 1
        for step in 0...260 {
            let top = 72 + CGFloat(step) / 10
            let layout = TrayLayout.rendered(
                topEdge: top, size: CGSize(width: 402, height: 874),
                topInset: 62, bottomInset: 34)
            #expect(layout.scale <= previousScale)
            #expect(previousScale - layout.scale < 0.001)
            #expect((0...8).contains(layout.bottomMargin))
            #expect(abs(874 - layout.bottomMargin - layout.height * layout.scale - top) < 0.001)
            previousScale = layout.scale
        }
        let middle = TrayLayout.rendered(
            topEdge: 85, size: CGSize(width: 402, height: 874), topInset: 62, bottomInset: 34)
        #expect(middle.bottomMargin == 4)
    }

    @Test func headerDismissalUsesDirectionDisplacementAndReleaseSpeed() {
        #expect(
            !TrayDrag.shouldDismiss(
                translation: CGSize(width: 0, height: -100),
                predicted: CGSize(width: 0, height: -200)))
        #expect(
            !TrayDrag.shouldDismiss(
                translation: CGSize(width: 100, height: 30),
                predicted: CGSize(width: 200, height: 300)))
        #expect(
            !TrayDrag.shouldDismiss(
                translation: CGSize(width: 0, height: 30),
                predicted: CGSize(width: 0, height: 80)))
        #expect(
            TrayDrag.shouldDismiss(
                translation: CGSize(width: 0, height: 90),
                predicted: CGSize(width: 0, height: 90)))
        #expect(
            TrayDrag.shouldDismiss(
                translation: CGSize(width: 0, height: 30),
                predicted: CGSize(width: 0, height: 200)))
    }

    private func makeRouter() -> Router {
        withDependencies {
            $0.calendar = Calendar(identifier: .gregorian)
        } operation: {
            Router()
        }
    }
}
