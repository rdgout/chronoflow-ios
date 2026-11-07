import CoreGraphics
import Testing

struct AuthScrollGestureTests {
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
