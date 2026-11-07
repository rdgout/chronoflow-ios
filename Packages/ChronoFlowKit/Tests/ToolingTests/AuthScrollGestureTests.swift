import CoreGraphics
import Testing

struct AuthScrollGestureTests {
    @Test func duoGestureStartsAboveTheRecordedKeyboardInsteadOfOnIt() throws {
        let viewport = CGRect(x: 0, y: 0, width: 382, height: 414)
        let toggle = CGRect(x: 36, y: 382, width: 310, height: 44)
        let gesture = try #require(AuthScrollGesture.reveal(toggle, in: viewport))
        #expect(viewport.contains(gesture.start))
        #expect(viewport.contains(gesture.end))
        #expect(gesture.start.y < 414)
        #expect(gesture.start.y - gesture.end.y >= toggle.maxY - viewport.maxY)
        #expect(!viewport.contains(CGPoint(x: 233, y: 439)))
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
