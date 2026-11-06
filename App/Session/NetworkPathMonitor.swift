import Foundation
import Network
import Sync

actor NetworkPathMonitor: SyncPathMonitoring {
    private var monitor: NWPathMonitor?
    private var continuation: AsyncStream<Bool>.Continuation?

    func updates() -> AsyncStream<Bool> {
        continuation?.finish()
        monitor?.cancel()
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let monitor = NWPathMonitor()
        self.continuation = continuation
        self.monitor = monitor
        monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
        monitor.start(queue: DispatchQueue(label: "net.chronoflow.sync.path"))
        return stream
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        continuation?.finish()
        continuation = nil
    }
}
