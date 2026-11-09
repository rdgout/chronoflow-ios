#if canImport(UIKit)
    import UIKit

    func pixels(_ image: UIImage) -> [UInt8] {
        try! SnapshotRaster(image: image.cgImage!).bytes
    }

#endif
