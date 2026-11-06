import Foundation

public protocol DeviceIdentityPersistence: Sendable {
    func readDeviceID() async throws -> String?
    func writeDeviceID(_ value: String) async throws
}

public enum DeviceIdentityFailure: Error, Sendable, Equatable {
    case invalidTimestamp, invalidRandomness, invalidPersistedIdentity
}

public struct UUIDv7: Sendable {
    public static func generate(millisecondsSince1970 timestamp: UInt64, randomBytes: [UInt8]) throws -> UUID {
        guard timestamp < (1 << 48) else { throw DeviceIdentityFailure.invalidTimestamp }
        guard randomBytes.count == 10 else { throw DeviceIdentityFailure.invalidRandomness }
        let bytes: [UInt8] =
            (0..<6).map { UInt8(truncatingIfNeeded: timestamp >> ((5 - $0) * 8)) }
            + [0x70 | (randomBytes[0] & 0x0f), randomBytes[1], 0x80 | (randomBytes[2] & 0x3f)]
            + Array(randomBytes[3...9])
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

public actor DeviceIdentityStore {
    private let persistence: any DeviceIdentityPersistence
    private let clock: @Sendable () -> Date
    private let randomBytes: @Sendable () throws -> [UInt8]
    private var cached: String?
    private var inFlight: Task<String, any Error>?
    private var generation: UInt64 = 0

    public init(
        persistence: any DeviceIdentityPersistence,
        clock: @escaping @Sendable () -> Date = { Date() },
        randomBytes: @escaping @Sendable () throws -> [UInt8] = {
            var generator = SystemRandomNumberGenerator()
            return (0..<10).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
    ) {
        self.persistence = persistence
        self.clock = clock
        self.randomBytes = randomBytes
    }

    public func identity() async throws -> String {
        try Task.checkCancellation()
        if let cached { return cached }
        if inFlight == nil {
            generation &+= 1
            inFlight = Task { [persistence, clock, randomBytes] in
                if let value = try await persistence.readDeviceID() {
                    guard let id = UUID(uuidString: value), value.count == 36,
                        id.uuid.6 >> 4 == 7, id.uuid.8 & 0xc0 == 0x80
                    else { throw DeviceIdentityFailure.invalidPersistedIdentity }
                    return id.uuidString.lowercased()
                }
                let milliseconds = floor(clock().timeIntervalSince1970 * 1000)
                guard milliseconds.isFinite, milliseconds >= 0, milliseconds < Double(1 << 48) else {
                    throw DeviceIdentityFailure.invalidTimestamp
                }
                let value = try UUIDv7.generate(millisecondsSince1970: UInt64(milliseconds), randomBytes: randomBytes())
                    .uuidString.lowercased()
                try await persistence.writeDeviceID(value)
                return value
            }
        }
        let flightGeneration = generation
        do {
            let value = try await inFlight!.value
            if generation == flightGeneration {
                cached = value
                inFlight = nil
            }
            try Task.checkCancellation()
            return value
        } catch {
            if generation == flightGeneration { inFlight = nil }
            throw error
        }
    }

    public static func deviceName(_ name: String, model: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = model.trimmingCharacters(in: .whitespacesAndNewlines)
        var count = 0
        return String(
            (trimmed.isEmpty ? fallback : trimmed).prefix { character in
                count += character.unicodeScalars.count
                return count <= 255
            })
    }
}
