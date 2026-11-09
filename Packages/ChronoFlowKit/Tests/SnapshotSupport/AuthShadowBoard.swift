import CoreGraphics

public nonisolated enum AuthShadowBoard {
    public static let size = CGSize(width: 375, height: 812)
    public static let scale: CGFloat = 3

    public struct Sample: Sendable {
        public let name: String
        public let pixels: CGRect
        public let light: [Double]
        public let dark: [Double]
        public let minimumLightInk: Double
        public let minimumDarkInk: Double

        public func mean(in raster: SnapshotRaster) -> [Double] {
            let scale = CGFloat(raster.width) / (AuthShadowBoard.size.width * AuthShadowBoard.scale)
            let xs = Int(ceil(pixels.minX * scale))..<Int(ceil(pixels.maxX * scale))
            let ys = Int(ceil(pixels.minY * scale))..<Int(ceil(pixels.maxY * scale))
            var sums = [Double](repeating: 0, count: 3)
            for y in ys {
                for x in xs {
                    for channel in 0..<3 { sums[channel] += Double(raster.bytes[(y * raster.width + x) * 4 + channel]) }
                }
            }
            return sums.map { $0 / Double(xs.count * ys.count) }
        }
    }

    // sRGB means from the eight Chrome board exports; regions avoid card and footer antialiasing.
    public static let samples = [
        Sample(
            name: "below", pixels: CGRect(x: 555, y: 2188, width: 11, height: 31),
            light: [186.01, 126.20, 110.77], dark: [106.94, 58.82, 46.92], minimumLightInk: 8, minimumDarkInk: 20),
        Sample(
            name: "beside", pixels: CGRect(x: 1080, y: 1495, width: 41, height: 11),
            light: [95.55, 77.76, 125.51], dark: [35.00, 26.12, 59.03], minimumLightInk: 1, minimumDarkInk: 2),
    ]
}
