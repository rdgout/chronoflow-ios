#if canImport(UIKit)
    import DesignSystem
    import UIKit

    extension LaunchScene {
        func buildLayers() {
            let appearance: TokenAppearance = traits.userInterfaceStyle == .dark ? .dark : .light
            let dawn = ColorToken.dawn.components(for: appearance).cgColor
            let horizon = ColorToken.skyHorizon.components(for: appearance).cgColor
            let white = LaunchPaint.white.cgColor
            container.bounds = CGRect(origin: .zero, size: size)
            container.anchorPoint = CGPoint(x: 0.5, y: 0.4)
            container.position = CGPoint(x: size.width / 2, y: size.height * 0.4)
            container.backgroundColor = ColorToken.skyTop.components(for: appearance).cgColor
            container.masksToBounds = true
            container.name = LayerID.container.rawValue
            layers[.container] = container

            let sky = CfSkyLayer()
            sky.appearance = appearance
            sky.frame = container.bounds
            add(sky, as: .sky)
            let stars = CALayer()
            stars.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.6)
            let tile = UIImage(
                cgImage: PatternDots.tile(color: LaunchPaint.white, scale: traits.displayScale),
                scale: traits.displayScale, orientation: .up)
            stars.backgroundColor = UIColor(patternImage: tile).cgColor
            add(stars, as: .stars)

            let centre = CGPoint(x: size.width / 2, y: size.height - 194)
            let halo = LaunchRadialLayer(
                size: 500, centre: centre, radius: 250, color: dawn,
                stops: LaunchGlow.haloStops, scale: traits.displayScale)
            add(halo, as: .halo)
            let sun = LaunchRadialLayer(
                size: 180, centre: centre, radius: 127.3, color: dawn,
                stops: [(0, 1), (70 / 127.3, 1), (91.6 / 127.3, 0), (1, 0)], scale: traits.displayScale)
            sun.cornerRadius = 90
            sun.masksToBounds = true
            add(sun, as: .sun)
            let band = CAGradientLayer()
            band.frame = CGRect(x: 0, y: size.height - 374, width: size.width, height: 374)
            band.colors = [0, 0.22, 0.70, 1].map { horizon.copy(alpha: $0)! }
            band.locations = [0, 0.4, 0.75, 1]
            add(band, as: .band)

            let path = CAShapeLayer()
            path.frame = container.bounds
            path.path = FlightPath(size: size).path
            path.fillColor = nil
            path.strokeColor = white.copy(alpha: 0.55)
            path.lineWidth = 1.5
            path.lineCap = .butt
            add(path, as: .path)
            let plane = CALayer()
            plane.bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
            plane.contents = LaunchGlow.plane(color: white, scale: traits.displayScale)
            add(plane, as: .plane)

            let moon = CALayer()
            let moonImage = LaunchImages.moon(compatibleWith: traits)
            moon.bounds = CGRect(origin: .zero, size: moonImage.size)
            moon.contents = moonImage.cgImage
            moon.minificationFilter = .trilinear
            add(moon, as: .moon)
            let wordmark = CALayer()
            let wordmarkImage = LaunchImages.wordmark(compatibleWith: traits)
            wordmark.bounds = CGRect(origin: .zero, size: wordmarkImage.size)
            wordmark.position = CGPoint(x: size.width / 2, y: size.height / 2 + 60)
            wordmark.contents = wordmarkImage.cgImage
            add(wordmark, as: .wordmark)
            statusLine.frame = CGRect(x: 0, y: size.height / 2 + 96, width: size.width, height: 20)
            statusLine.configure(
                color: ColorToken.skyTitle.components(for: appearance).cgColor,
                scale: traits.displayScale)
            add(statusLine, as: .status)
            layers[.statusDot] = statusLine.dot
            statusLine.dot.name = LayerID.statusDot.rawValue
        }

        private func add(_ layer: CALayer, as id: LayerID) {
            layer.name = id.rawValue
            layer.contentsScale = traits.displayScale
            container.addSublayer(layer)
            layers[id] = layer
        }

    }
#endif
