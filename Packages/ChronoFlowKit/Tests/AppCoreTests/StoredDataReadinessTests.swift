import Foundation
import Testing

@testable import AppCore

private let readinessID = "019a562b-8000-7000-8000-000000000001"

private actor ReadinessValues {
    var value: StoredAccountReadiness?
    var fails = false
    private var continuations: [UUID: StoredDataReadiness.Values.Continuation] = [:]
    private(set) var reads = 0
    init(gate: Gate? = .app, stored: Bool = false) {
        value = StoredAccountReadiness(accountID: readinessID, gate: gate, hasStoredData: stored)
    }
    func values() throws -> StoredDataReadiness.Values {
        reads += 1
        if fails { throw SessionFailure.databaseUnavailable }
        let id = UUID()
        let (stream, continuation) = StoredDataReadiness.Values.makeStream()
        continuations[id] = continuation
        continuation.yield(value)
        continuation.onTermination = { _ in Task { await self.remove(id) } }
        return stream
    }
    private func remove(_ id: UUID) { continuations.removeValue(forKey: id) }
    func set(gate: Gate? = .app, stored: Bool) {
        value = StoredAccountReadiness(accountID: readinessID, gate: gate, hasStoredData: stored)
        for continuation in continuations.values { continuation.yield(value) }
    }
    func setFails(_ fails: Bool) { self.fails = fails }
}

private func readinessController(_ credentials: ControllerMemoryStore) -> SessionController {
    SessionController(credentials: credentials, accounts: ControllerAccountStore(log: SessionEventLog()))
}
private func readinessCredentials() throws -> ControllerMemoryStore {
    ControllerMemoryStore(
        try JSONEncoder().encode(StoredSession(token: "test-token", accountId: readinessID)), log: SessionEventLog())
}

@Suite struct StoredDataReadinessTests {
    @Test func cachedOfflineAndFreshMarkerStreamNeverFakesSyncedAt() async throws {
        let credentials = try readinessCredentials()
        let controller = readinessController(credentials)
        let values = ReadinessValues(stored: true)
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        #expect(await source.session() == .signedIn(accountID: readinessID))
        #expect(await source.gate() == .app)
        #expect(await source.hasStoredData())
        await values.set(stored: false)
        let stream = await source.storedDataUpdates()
        defer { withExtendedLifetime(stream) {} }
        var updates = stream.makeAsyncIterator()
        #expect(await updates.next() == false)
        await source.allowFirstLoad()
        #expect(await source.firstLoadEpoch == controller.epoch)
        #expect(await source.hasStoredData() == false)
        await values.set(stored: true)
        let next = await updates.next()
        #expect(next == true)
    }

    @Test func protectedCredentialFailureStaysUnknownAndRetriesOnActivation() async throws {
        let credentials = try readinessCredentials()
        let original = await credentials.data
        await credentials.configure(readFails: true)
        let controller = readinessController(credentials)
        let values = ReadinessValues()
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        let task = Task { await source.session() }
        while await source.failure == nil { await Task.yield() }
        #expect(await source.failure == .credentialsUnavailable)
        #expect(await controller.presence == nil)
        #expect(await credentials.data == original)
        await credentials.configure()
        await source.retry()
        #expect(await task.value == .signedIn(accountID: readinessID))
        #expect(await source.failure == nil)
    }

    @Test func cancellationOfUnknownSessionPreservesCredentialsAndStartsNoObservation() async throws {
        let credentials = try readinessCredentials()
        await credentials.configure(readFails: true)
        let controller = readinessController(credentials)
        let values = ReadinessValues()
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        let task = Task { await source.session() }
        while await source.failure == nil { await Task.yield() }
        task.cancel()
        _ = await task.value
        #expect(await controller.presence == nil)
        #expect(await credentials.deletes == 0)
        #expect(await values.reads == 0)
    }

    @Test func unavailableObservationWaitsForRetryAndEmptyReadIsFalse() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues()
        await values.setFails(true)
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        _ = await source.session()
        let read = Task { await source.hasStoredData() }
        while await source.failure == nil { await Task.yield() }
        #expect(await source.failure == .databaseUnavailable)
        await values.setFails(false)
        await source.retry()
        #expect(await read.value == false)
    }

    @Test @MainActor func freshDataKeepsTwoAndEightSecondRules() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues()
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        let clock = ManualLaunchClock()
        let coordinator = LaunchCoordinator(readiness: source, clock: clock, reduceMotion: false) { _, _ in }
        coordinator.start()
        defer { coordinator.stop() }
        while coordinator.state.hasStoredData == nil { await Task.yield() }
        clock.advance(to: .seconds(2))
        while !coordinator.state.showsStatus { await Task.yield() }
        #expect(!coordinator.state.isReady)
        clock.advance(to: .seconds(8))
        while !coordinator.state.didForceReady { await Task.yield() }
        while await source.firstLoadEpoch == nil { await Task.yield() }
        #expect(coordinator.state.route == .today)
        #expect(await source.hasStoredData() == false)
    }

    @Test @MainActor func verificationIsReadyWithoutMarkerAndSignedOutDoesNotReadDatabase() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues(gate: .verify)
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        let coordinator = LaunchCoordinator(readiness: source, clock: ManualLaunchClock(), reduceMotion: false) {
            _, _ in
        }
        coordinator.start()
        defer { coordinator.stop() }
        while coordinator.state.gate == nil { await Task.yield() }
        #expect(coordinator.state.route == .verify)
        #expect(coordinator.state.isReady)
        let signedOut = StoredDataReadiness(
            controller: readinessController(ControllerMemoryStore(log: SessionEventLog())),
            values: { _ in
                Issue.record("Signed-out launch read the database")
                return AsyncThrowingStream { $0.finish() }
            })
        #expect(await signedOut.session() == .signedOut)
        #expect(SignedOutReadiness().session() == .signedOut)
    }
}

extension StoredDataReadinessTests {
    @Test @MainActor func committedVerificationRoutingSurvivesRequestCancellationAndRestore() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues(gate: .verify)
        let readiness = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        _ = try await controller.restore()
        let navigator = GateNavigatorProbe()
        for _ in 0..<2 {
            let snapshot = try #require(await controller.activeSession())
            let request = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                await readiness.routeAcceptedSession(navigator: navigator) { epoch in
                    #expect(!Task.isCancelled)
                    #expect(epoch == snapshot.epoch)
                    navigator.navigate(to: .verify)
                }
            }
            await request.value
            #expect(navigator.routes.last == .verify)
            _ = try await controller.restore()
        }
        #expect(navigator.routes == [.verify, .verify])
    }

    @Test @MainActor func unknownSessionUsesExistingEightSecondFallbackWithoutDeletingData() async throws {
        let credentials = try readinessCredentials()
        await credentials.configure(readFails: true)
        let controller = readinessController(credentials)
        let source = StoredDataReadiness(
            controller: controller,
            values: { _ in
                Issue.record("Unavailable credentials opened observation")
                return AsyncThrowingStream { $0.finish() }
            })
        let clock = ManualLaunchClock()
        let coordinator = LaunchCoordinator(readiness: source, clock: clock, reduceMotion: false) { _, _ in }
        coordinator.start()
        defer { coordinator.stop() }
        while await source.failure == nil { await Task.yield() }
        clock.advance(to: .seconds(8))
        while !coordinator.state.didForceReady { await Task.yield() }
        #expect(coordinator.state.session == .signedOut)
        #expect(coordinator.state.route == .welcome)
        #expect(await controller.presence == nil)
        #expect(await credentials.data != nil)
        #expect(await credentials.deletes == 0)
    }
}

extension StoredDataReadinessTests {
    @Test @MainActor func verificationDiscoveredDuringFirstPullReleasesLaunchWithoutMarker() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues()
        let source = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        let coordinator = LaunchCoordinator(readiness: source, clock: ManualLaunchClock(), reduceMotion: false) {
            _, _ in
        }
        coordinator.start()
        defer { coordinator.stop() }
        while coordinator.state.gate == nil || coordinator.state.hasStoredData == nil { await Task.yield() }
        #expect(!coordinator.state.isReady)
        await values.set(gate: .verify, stored: false)
        while coordinator.state.gate != .verify { await Task.yield() }
        #expect(coordinator.state.isReady)
        #expect(coordinator.state.route == .verify)
        #expect(!coordinator.state.didForceReady)
    }
}

@MainActor private final class GateNavigatorProbe: Navigator {
    var routes: [Route] = []
    func navigate(to route: Route) { routes.append(route) }
}

extension StoredDataReadinessTests {
    @Test @MainActor func gatesContinueAfterAcceptanceAndCancelAtSignOut() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues(gate: .verify)
        let readiness = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        _ = await readiness.session()
        let navigator = GateNavigatorProbe()
        let router = SessionGateRouter(controller: controller, readiness: readiness, navigator: navigator) { _ in
            navigator.navigate(to: .verify)
        }
        router.start()
        defer { router.stop() }
        for (gate, route) in [
            (Gate.verify, Route.verify), (.terms, .terms), (.walkthrough, .walkthrough), (.app, .today),
        ] {
            await values.set(gate: gate, stored: true)
            let deadline = ContinuousClock.now + .seconds(3)
            while navigator.routes.last != route && ContinuousClock.now < deadline { await Task.yield() }
            #expect(navigator.routes.last == route)
        }
        _ = try await controller.signOut(discardPending: true)
        let deadline = ContinuousClock.now + .seconds(3)
        while navigator.routes.last != .signIn && ContinuousClock.now < deadline { await Task.yield() }
        #expect(navigator.routes.last == .signIn)
        let count = navigator.routes.count
        await values.set(gate: .terms, stored: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(navigator.routes.count == count)
    }

    @Test @MainActor func signedOutRoutesAndRevokesMutationsBeforeLogoutFinishes() async throws {
        let logout = SessionTestGate()
        var teardown = SessionTeardown()
        teardown.logout = { _ in await logout.wait() }
        let controller = SessionController(
            credentials: try readinessCredentials(), accounts: ControllerAccountStore(log: SessionEventLog()),
            teardown: teardown)
        let values = ReadinessValues(stored: true)
        let readiness = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        _ = await readiness.session()
        let snapshot = try #require(await controller.activeSession())
        let permit = try #require(await controller.mutationPermit(for: snapshot))
        #expect(try permit.whileValid { true })
        let navigator = GateNavigatorProbe()
        let router = SessionGateRouter(controller: controller, readiness: readiness, navigator: navigator) { _ in }
        router.start()
        defer { router.stop() }
        let deadline = ContinuousClock.now + .seconds(3)
        while navigator.routes.last != .today && ContinuousClock.now < deadline { await Task.yield() }
        #expect(navigator.routes.last == .today)
        let signOut = Task { try await controller.signOut(discardPending: true) }
        await logout.waitUntilEntered()
        while navigator.routes.last != .signIn && ContinuousClock.now < deadline { await Task.yield() }
        #expect(navigator.routes.last == .signIn)
        #expect(throws: CancellationError.self) { try permit.whileValid { Issue.record("Revoked mutation ran") } }
        #expect(await controller.mutationPermit(for: snapshot) == nil)
        await values.set(gate: .terms, stored: true)
        for _ in 0..<20 { await Task.yield() }
        #expect(navigator.routes.last == .signIn)
        await logout.release()
        #expect(try await signOut.value == .signedOut)
    }

    @Test @MainActor func initiallySignedOutKeepsWelcomeRoute() async {
        let controller = readinessController(ControllerMemoryStore(log: SessionEventLog()))
        _ = try? await controller.restore()
        let readiness = StoredDataReadiness(
            controller: controller, values: { _ in AsyncThrowingStream { $0.finish() } })
        let navigator = GateNavigatorProbe()
        let router = SessionGateRouter(controller: controller, readiness: readiness, navigator: navigator) { _ in }
        router.start()
        defer { router.stop() }
        for _ in 0..<20 { await Task.yield() }
        #expect(navigator.routes.isEmpty)
    }

    @Test func missingPoliciesWaitUntilLoadedOrExplicitFirstLoadAllowance() async throws {
        let controller = readinessController(try readinessCredentials())
        let values = ReadinessValues(gate: nil)
        let readiness = StoredDataReadiness(controller: controller, values: { _ in try await values.values() })
        _ = await readiness.session()
        var gates = await readiness.gateUpdates().makeAsyncIterator()
        await values.set(gate: .terms, stored: true)
        #expect(await gates.next() == .terms)
        await values.set(gate: nil, stored: false)
        var firstLoad = await readiness.gateUpdates().makeAsyncIterator()
        await readiness.allowFirstLoad()
        #expect(await firstLoad.next() == .app)
        await values.set(gate: .terms, stored: true)
        #expect(await firstLoad.next() == .terms)
    }
}
