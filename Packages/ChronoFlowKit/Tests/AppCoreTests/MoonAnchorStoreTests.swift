import CoreGraphics
import Testing

@testable import AppCore

@MainActor struct MoonAnchorStoreTests {
    @Test func publishesValidChangedFramesAndRejectsInvalidGeometry() {
        let store = MoonAnchorStore()
        var frames: [CGRect] = []
        store.onChange = { frames.append($0) }
        let first = CGRect(x: 24, y: 64, width: 28, height: 28)
        store.update(.zero)
        store.update(.null)
        store.update(.infinite)
        store.update(CGRect(x: CGFloat.nan, y: 0, width: 28, height: 28))
        #expect(store.frame == nil)
        store.update(first)
        store.update(first)
        store.update(first.offsetBy(dx: 31, dy: 16))
        #expect(frames == [first, first.offsetBy(dx: 31, dy: 16)])
        #expect(store.frame == frames.last)
    }

    @Test func measuredAnchorRebuildsTheReducerBeforeFlightOnly() {
        let store = MoonAnchorStore()
        var state = LaunchState()
        _ = reduce(&state, .session(.signedOut), reduceMotion: false)
        var effects: [LaunchEffect] = []
        store.onChange = { effects += reduce(&state, .moonAnchor($0), reduceMotion: false) }
        let first = CGRect(x: 24, y: 64, width: 28, height: 28)
        store.update(first)
        let changed = first.offsetBy(dx: 31, dy: 16)
        store.update(changed)
        #expect(effects.count == 2)
        #expect(state.moonTarget == changed)
        _ = reduce(&state, .reached(.milliseconds(1600)), reduceMotion: false)
        store.update(first)
        #expect(effects.count == 2)
        #expect(state.moonTarget == changed)
    }
}
