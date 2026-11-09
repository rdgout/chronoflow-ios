import CoreGraphics
import Testing

struct AuthScrollGestureTests {
    @Test func auditCoverageRequiresTheWholeControlInsideTheSafeKeyboardViewport() {
        let window = CGRect(x: 0, y: 0, width: 390, height: 844)
        let safeArea = CGRect(x: 0, y: 47, width: 390, height: 763)
        let keyboard = CGRect(x: 0, y: 550, width: 390, height: 294)
        let viewport = AuthScrollGesture.viewport(
            window: window, safeArea: safeArea, scroll: window, keyboard: keyboard)
        let footer = CGRect(x: 16, y: 791, width: 358, height: 48)
        let consent = CGRect(x: 48, y: 530, width: 294, height: 39)
        let visible = CGRect(x: 36, y: 490, width: 318, height: 44)
        #expect(AuthScrollGesture.fullyVisible(visible, in: viewport))
        #expect(!AuthScrollGesture.fullyVisible(footer, in: viewport))
        #expect(!AuthScrollGesture.fullyVisible(consent, in: viewport))
        #expect(!AuthScrollGesture.fullyVisible(footer, in: safeArea))
        #expect(AuthScrollGesture.fullyVisible(footer.offsetBy(dx: 0, dy: -310), in: viewport))
        #expect(AuthScrollGesture.fullyVisible(CGRect(x: 36, y: 506, width: 318, height: 44.000001), in: viewport))
        #expect(!AuthScrollGesture.fullyVisible(CGRect(x: 36, y: 506, width: 318, height: 44.1), in: viewport))
        for invalid in [CGRect.zero, .null, .infinite] {
            #expect(!AuthScrollGesture.fullyVisible(invalid, in: viewport))
            #expect(!AuthScrollGesture.fullyVisible(visible, in: invalid))
        }
    }

    @Test func navigationViewportIncludesBackButtonWithoutChangingContentOrKeyboardBounds() {
        let window = CGRect(x: 10, y: 20, width: 390, height: 844)
        let safeArea = window.insetBy(dx: 24, dy: 47)
        let keyboard = CGRect(x: window.minX, y: 580, width: window.width, height: 284)
        let back = CGRect(x: safeArea.minX, y: window.minY + 15, width: 44, height: 44)
        for keyboard in [nil, keyboard] {
            let content = AuthScrollGesture.viewport(
                window: window, safeArea: safeArea, scroll: safeArea, keyboard: keyboard)
            let navigation = AuthScrollGesture.viewport(
                window: window, safeArea: safeArea, scroll: safeArea, keyboard: keyboard, includingNavigationBar: true)
            #expect(!content.contains(back))
            #expect(navigation.contains(back))
            #expect(navigation.minY == window.minY)
            #expect(navigation.minX == content.minX)
            #expect(navigation.maxX == content.maxX)
            #expect(navigation.maxY == content.maxY)
            #expect(AuthScrollGesture.reveal(back, in: navigation) == nil)
        }
    }

    @Test func duoGestureStartsAboveTheRecordedKeyboardInsteadOfOnIt() throws {
        let window = CGRect(x: 0, y: 0, width: 466, height: 678)
        let safeArea = window.insetBy(dx: 24, dy: 20)
        let keyboard = CGRect(x: 0, y: 414, width: 466, height: 264)
        let toggle = CGRect(x: 36, y: 422, width: 310, height: 44)
        let viewport = AuthScrollGesture.viewport(
            window: window, safeArea: safeArea, scroll: window, keyboard: keyboard)
        let gesture = try #require(AuthScrollGesture.reveal(toggle, in: viewport))
        #expect(viewport.maxY == keyboard.minY)
        #expect(viewport.minX == safeArea.minX)
        #expect(viewport.maxX == safeArea.maxX)
        #expect(viewport.contains(gesture.start))
        #expect(viewport.contains(gesture.end))
        #expect(gesture.start.y < keyboard.minY)
        #expect(gesture.start.y - gesture.end.y >= toggle.maxY - viewport.maxY)
        #expect(!keyboard.contains(gesture.start))

        let unclipped = AuthScrollGesture.viewport(window: window, safeArea: safeArea, scroll: window, keyboard: nil)
        #expect(unclipped.maxY == safeArea.maxY)
        #expect(AuthScrollGesture.reveal(toggle, in: unclipped) == nil)
        let oldStart = CGPoint(x: window.midX, y: 439)
        #expect(keyboard.contains(oldStart))
        #expect(!viewport.contains(oldStart))
        #expect(oldStart.y >= keyboard.minY)

        let raisedKeyboard = keyboard.offsetBy(dx: 0, dy: -60)
        let raisedViewport = AuthScrollGesture.viewport(
            window: window, safeArea: safeArea, scroll: window, keyboard: raisedKeyboard)
        let raisedGesture = try #require(AuthScrollGesture.reveal(toggle, in: raisedViewport))
        #expect(raisedViewport.maxY == raisedKeyboard.minY)
        #expect(raisedGesture.start.y < raisedKeyboard.minY)
        #expect(raisedGesture.start.y < gesture.start.y)
    }

    @Test func gesturesStayInsideShortAndAsymmetricViewportsInBothDirections() throws {
        for viewport in [CGRect(x: 24, y: 20, width: 310, height: 180), CGRect(x: 0, y: 20, width: 375, height: 429)] {
            for y in [viewport.minY - 200, viewport.maxY + 200] {
                let frame = CGRect(x: viewport.minX, y: y, width: viewport.width, height: 44)
                let gesture = try #require(AuthScrollGesture.reveal(frame, in: viewport))
                #expect(viewport.contains(gesture.start))
                #expect(viewport.contains(gesture.end))
                #expect((gesture.start.y > gesture.end.y) == (frame.maxY > viewport.maxY))
            }
        }
        #expect(AuthScrollGesture.reveal(.zero, in: .zero) == nil)
        #expect(
            AuthScrollGesture.reveal(
                CGRect(x: 10, y: 10, width: 44, height: 44), in: CGRect(x: 0, y: 0, width: 100, height: 100)) == nil)
    }
}
