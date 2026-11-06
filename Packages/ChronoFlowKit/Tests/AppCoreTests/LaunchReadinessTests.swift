import CoreGraphics
import Foundation
import Testing

@testable import AppCore

struct LaunchReadinessTests {
    private let target = CGRect(x: 38, y: 64, width: 28, height: 28)

    @Test func endingIsChosenOnceAndIntentNeverRoutes() throws {
        let url = try #require(URL(string: "https://chronoflow.net/trips/42"))
        var state = LaunchState(fallbackTarget: target, pendingIntent: .init(urls: [url]))
        #expect(reduce(&state, .session(.signedOut), reduceMotion: false).isEmpty)
        _ = reduce(&state, .session(.signedIn(accountID: "later")), reduceMotion: false)
        #expect(state.ending == .welcome)
        #expect(state.route == .welcome)
        #expect(state.isReady)
        #expect(state.pendingIntent.urls == [url])
    }

    @Test func appWaitsForBothGateAndStoredDataThenCommitsAhead() {
        var state = LaunchState()
        #expect(reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false).isEmpty)
        #expect(reduce(&state, .storedData(true), reduceMotion: false).isEmpty)
        #expect(!state.isReady)
        #expect(
            reduce(&state, .gate(.app), reduceMotion: false) == [
                .commitExit(.app, at: .milliseconds(1500), moonTarget: nil)
            ])
        #expect(state.route == .today)
        for time in [1400, 1500, 2000, 8000, 9000] {
            #expect(reduce(&state, .reached(.milliseconds(time)), reduceMotion: false).isEmpty)
        }
    }

    @Test(arguments: [Gate.terms, .verify, .walkthrough])
    func nonAppGatesAreReadyWithoutStoredData(_ gate: Gate) {
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        let effects = reduce(&state, .gate(gate), reduceMotion: false)
        #expect(state.isReady)
        #expect(state.route == gate.route)
        #expect(effects == [.commitExit(.app, at: .milliseconds(1500), moonTarget: nil)])
    }

    @Test func lateReadyStartsAtReadinessAndStatusIsLatched() {
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        _ = reduce(&state, .gate(.app), reduceMotion: false)
        #expect(reduce(&state, .storedData(false), reduceMotion: false) == [.commitStatus(at: .seconds(2))])
        #expect(!state.showsStatus)
        _ = reduce(&state, .reached(.seconds(2)), reduceMotion: false)
        #expect(state.showsStatus)
        _ = reduce(&state, .reached(.milliseconds(3500)), reduceMotion: false)
        #expect(
            reduce(&state, .storedData(true), reduceMotion: false) == [
                .commitExit(.app, at: .milliseconds(3500), moonTarget: nil)
            ])
        #expect(state.showsStatus)
        #expect(state.statusStart == .seconds(2))
    }

    @Test func statusRequiresExplicitFalseAndCancelsBeforeItsStart() {
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        #expect(reduce(&state, .reached(.milliseconds(1900)), reduceMotion: false).isEmpty)
        #expect(state.statusStart == nil)
        _ = reduce(&state, .storedData(false), reduceMotion: false)
        #expect(
            reduce(&state, .gate(.terms), reduceMotion: false) == [
                .cancelStatus, .commitExit(.app, at: .milliseconds(1900), moonTarget: nil),
            ])
        _ = reduce(&state, .reached(.seconds(3)), reduceMotion: false)
        #expect(!state.showsStatus)
        #expect(state.statusStart == nil)
    }

    @Test func lateStoredFalseStartsStatusNowAndNeverForUnknown() {
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        #expect(reduce(&state, .reached(.seconds(4)), reduceMotion: false).isEmpty)
        #expect(!state.showsStatus)
        #expect(reduce(&state, .storedData(false), reduceMotion: false) == [.commitStatus(at: .seconds(4))])
        #expect(state.showsStatus)
    }

    @Test func timeoutForcesCurrentSessionOnceAndIgnoresLateFacts() {
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        #expect(
            reduce(&state, .reached(.seconds(8)), reduceMotion: false) == [
                .forceReady, .commitExit(.app, at: .seconds(8), moonTarget: nil),
            ])
        #expect(state.route == .today)
        #expect(reduce(&state, .reached(.seconds(9)), reduceMotion: false).isEmpty)
        #expect(reduce(&state, .gate(.verify), reduceMotion: false).isEmpty)
        #expect(reduce(&state, .session(.signedIn(accountID: "b")), reduceMotion: false).isEmpty)
        #expect(state.session == .signedIn(accountID: "a"))
    }

    @Test func unresolvedSessionDefaultsSignedOutAtEightSeconds() {
        var state = LaunchState(fallbackTarget: target)
        #expect(
            reduce(&state, .reached(.seconds(8)), reduceMotion: false) == [
                .commitExit(.welcome, at: .seconds(8), moonTarget: target)
            ])
        #expect(state.session == .signedOut)
        #expect(state.isReady)
        #expect(state.route == .welcome)
    }

    @Test func welcomeCommitsOnAnchorAndRebuildsOnlyBeforeFlight() {
        var state = LaunchState(fallbackTarget: target)
        _ = reduce(&state, .session(.signedOut), reduceMotion: false)
        let first = CGRect(x: 70, y: 90, width: 28, height: 28)
        #expect(
            reduce(&state, .moonAnchor(first), reduceMotion: false) == [
                .commitExit(.welcome, at: .milliseconds(1600), moonTarget: first)
            ])
        #expect(reduce(&state, .moonAnchor(first), reduceMotion: false).isEmpty)
        _ = reduce(&state, .reached(.milliseconds(1599)), reduceMotion: false)
        #expect(
            reduce(&state, .moonAnchor(target), reduceMotion: false) == [
                .commitExit(.welcome, at: .milliseconds(1600), moonTarget: target)
            ])
        _ = reduce(&state, .reached(.milliseconds(1600)), reduceMotion: false)
        #expect(reduce(&state, .moonAnchor(first), reduceMotion: false).isEmpty)
        #expect(state.moonTarget == target)
    }

    @Test func welcomeFallbackIsOnlyCommittedAtDeadlineAndCanBeReplaced() {
        var state = LaunchState(fallbackTarget: target)
        _ = reduce(&state, .session(.signedOut), reduceMotion: false)
        #expect(reduce(&state, .reached(.milliseconds(1549)), reduceMotion: false).isEmpty)
        #expect(
            reduce(&state, .reached(.milliseconds(1550)), reduceMotion: false) == [
                .commitExit(.welcome, at: .milliseconds(1600), moonTarget: target)
            ])
        let measured = CGRect(x: 61, y: 103, width: 28, height: 28)
        #expect(
            reduce(&state, .moonAnchor(measured), reduceMotion: false) == [
                .commitExit(.welcome, at: .milliseconds(1600), moonTarget: measured)
            ])
        _ = reduce(&state, .exitCompleted, reduceMotion: false)
        #expect(reduce(&state, .reached(.seconds(8)), reduceMotion: false).isEmpty)
        #expect(reduce(&state, .moonAnchor(target), reduceMotion: false).isEmpty)
    }

    @Test func invalidAnchorsAreIgnored() {
        var state = LaunchState(fallbackTarget: target)
        _ = reduce(&state, .session(.signedOut), reduceMotion: false)
        for rect in [
            CGRect.zero, .null, .infinite,
            CGRect(x: CGFloat.nan, y: 0, width: 28, height: 28),
            CGRect(x: 0, y: CGFloat.infinity, width: 28, height: 28),
        ] {
            #expect(reduce(&state, .moonAnchor(rect), reduceMotion: false).isEmpty)
            #expect(state.moonTarget == nil)
        }
    }

    @Test func lateSignedOutStartsAtResolution() {
        var state = LaunchState(fallbackTarget: target)
        _ = reduce(&state, .reached(.seconds(3)), reduceMotion: false)
        #expect(
            reduce(&state, .session(.signedOut), reduceMotion: false) == [
                .commitExit(.welcome, at: .seconds(3), moonTarget: target)
            ])
    }

    @Test(arguments: [true, false])
    func reduceMotionSkipsWaitAndAnchor(_ signedOut: Bool) {
        var state = LaunchState()
        if signedOut {
            #expect(
                reduce(&state, .session(.signedOut), reduceMotion: true) == [
                    .commitExit(.welcome, at: .zero, moonTarget: .zero)
                ])
        } else {
            _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: true)
            #expect(
                reduce(&state, .gate(.terms), reduceMotion: true) == [
                    .commitExit(.app, at: .zero, moonTarget: nil)
                ])
        }
    }
}
