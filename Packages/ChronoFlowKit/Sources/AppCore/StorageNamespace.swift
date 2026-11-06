public enum StorageNamespace: Sendable, CaseIterable {
    case api, mock

    public var directoryName: String { self == .api ? "ChronoFlow" : "ChronoFlowMock" }
    public var keychainService: String {
        self == .api ? "net.chronoflow.app.native" : "net.chronoflow.app.native.mock"
    }
}
