enum WelcomeSnapshotPixels {
    static func hasVisibleVariation(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 8, bytes.count.isMultiple(of: 4) else { return false }
        return stride(from: 4, to: bytes.count, by: 4).contains { offset in
            bytes[offset + 3] > 0 && (0..<4).contains { bytes[offset + $0] != bytes[$0] }
        }
    }

    static func differ(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        let different = zip(lhs, rhs).reduce(into: 0) { count, pair in
            if abs(Int(pair.0) - Int(pair.1)) > 8 { count += 1 }
        }
        return Double(different) / Double(lhs.count) > 0.001
    }
}
