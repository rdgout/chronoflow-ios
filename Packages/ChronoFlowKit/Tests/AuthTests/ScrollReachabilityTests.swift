import CoreGraphics
import SnapshotSupport
import Testing

struct ScrollReachabilityTests {
    @Test func reachesAboveBelowAndAlreadyVisibleFramesWithNonzeroInsets() {
        let viewport = CGRect(x: 24, y: 20, width: 300, height: 400)
        for (frame, offset) in [
            (CGRect(x: 24, y: 10, width: 300, height: 44), CGFloat(-10)),
            (CGRect(x: 24, y: 400, width: 300, height: 44), CGFloat(24)),
            (CGRect(x: 24, y: 200, width: 300, height: 44), CGFloat(0)),
        ] {
            let result = ScrollReachability.reveal(
                frame, viewport: viewport, currentOffset: 0, minimumOffset: -20, maximumOffset: 100)
            #expect(result.fits)
            #expect(result.offset == offset)
            #expect(viewport.contains(result.frame))
        }
    }

    @Test func usesTheCurrentOffsetAndRejectsClippingAtScrollLimitsOrRails() {
        let viewport = CGRect(x: 24, y: 20, width: 300, height: 400)
        let frame = CGRect(x: 24, y: 400, width: 300, height: 44)
        let result = ScrollReachability.reveal(
            frame, viewport: viewport, currentOffset: 50, minimumOffset: -20, maximumOffset: 100)
        #expect(result.offset == 74 && result.fits)
        for candidate in [
            frame.offsetBy(dx: -1, dy: 0), frame.offsetBy(dx: 1, dy: 0),
            frame.offsetBy(dx: 0, dy: 100), CGRect(x: 24, y: 20, width: 300, height: 401),
            .zero, .null, .infinite,
        ] {
            #expect(
                !ScrollReachability.reveal(
                    candidate, viewport: viewport, currentOffset: 0, minimumOffset: -20, maximumOffset: 100
                ).fits)
        }
        #expect(
            !ScrollReachability.reveal(
                frame, viewport: viewport, currentOffset: 0, minimumOffset: 100, maximumOffset: 0
            ).fits)
        #expect(
            !ScrollReachability.reveal(
                frame, viewport: viewport, currentOffset: .infinity, minimumOffset: 0, maximumOffset: 100
            ).fits)
    }
}
