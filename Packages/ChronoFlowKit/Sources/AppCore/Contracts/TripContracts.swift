import Foundation

public typealias CheckKey = CheckKeyView
public typealias CheckStateView = CheckState
public typealias CheckMarkView = CheckMark
public typealias TripCardProgress = TripProgress
public typealias GutterTickView = TickView

public struct TripCheckResult: Codable, Sendable, Equatable {
    public var checkState: CheckState
    public var detailVersion: String

    public init(checkState: CheckState, detailVersion: String) {
        self.checkState = checkState
        self.detailVersion = detailVersion
    }
}

@dynamicMemberLookup
public struct TripDetailResponse: Sendable, Equatable {
    public let data: Data
    public let detail: TripDetail

    public init(data: Data) throws {
        detail = try JSONDecoder().decode(TripDetail.self, from: data)
        self.data = data
    }

    public init(encoding detail: TripDetail) throws {
        try self.init(data: JSONEncoder().encode(detail))
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<TripDetail, Value>) -> Value {
        detail[keyPath: keyPath]
    }
}
