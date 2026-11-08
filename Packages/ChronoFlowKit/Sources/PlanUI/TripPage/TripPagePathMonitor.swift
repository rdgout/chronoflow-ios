import Foundation
import Network
import Sync

public actor TripPagePathMonitor: SyncPathMonitoring {
    private var monitor: NWPathMonitor?
    private var continuation: AsyncStream<Bool>.Continuation?

    public init() {}

    public func updates() -> AsyncStream<Bool> {
        stop()
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        self.monitor = monitor
        self.continuation = continuation
        continuation.onTermination = { _ in monitor.cancel() }
        monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
        monitor.start(queue: DispatchQueue(label: "net.chronoflow.trip.path"))
        return stream
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
        continuation?.finish()
        continuation = nil
    }
}
