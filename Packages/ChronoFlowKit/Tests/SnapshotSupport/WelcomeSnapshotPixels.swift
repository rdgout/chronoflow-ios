public nonisolated enum WelcomeSnapshotPixels {
    public static func hasVisibleVariation(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 8, bytes.count.isMultiple(of: 4) else { return false }
        return bytes.withUnsafeBytes { buffer in
            let pixels = buffer.baseAddress!.assumingMemoryBound(to: UInt32.self)
            let first = pixels[0]
            var index = 1
            while index < buffer.count / 4 {
                let pixel = pixels[index]
                if pixel != first && pixel.bigEndian & 0xff > 0 { return true }
                index += 1
            }
            return false
        }
    }

    public static func isFullyTransparent(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 4) else { return false }
        return bytes.withUnsafeBytes { buffer in
            let pixels = buffer.baseAddress!.assumingMemoryBound(to: UInt32.self)
            var index = 0
            while index < buffer.count / 4 {
                if pixels[index].bigEndian & 0xff != 0 { return false }
                index += 1
            }
            return true
        }
    }

    public static func differ(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        return lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in
                let left = left.baseAddress!
                let right = right.baseAddress!
                let limit = lhs.count / 1000
                var different = 0
                for index in 0..<lhs.count {
                    if abs(Int(left[index]) - Int(right[index])) > 8 {
                        different += 1
                        if different > limit { return true }
                    }
                }
                return false
            }
        }
    }
}
