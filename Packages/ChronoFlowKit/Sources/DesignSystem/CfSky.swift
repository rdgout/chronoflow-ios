import QuartzCore
import SwiftUI

nonisolated public final class CfSkyLayer: CAGradientLayer {
    public var appearance: TokenAppearance = .light {
        didSet { if oldValue != appearance { updateColors() } }
    }

    public override init() {
        super.init()
        startPoint = CGPoint(x: 0.5, y: 0)
        endPoint = CGPoint(x: 0.5, y: 1)
        updateColors()
    }

    public override init(layer: Any) {
        appearance = (layer as? CfSkyLayer)?.appearance ?? .light
        super.init(layer: layer)
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    private func updateColors() {
        let ramp = appearance == .light ? SkyRamp.light : SkyRamp.dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colors = ramp.map { $0.color.cgColor }
        locations = ramp.map { NSNumber(value: $0.location) }
        CATransaction.commit()
    }
}

public struct CfSky: View {
    @Environment(\.colorScheme) private var colorScheme
    public init() {}
    public var body: some View {
        NativeSky(appearance: colorScheme == .dark ? .dark : .light)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
    import UIKit

    private struct NativeSky: UIViewRepresentable {
        let appearance: TokenAppearance
        func makeUIView(context: Context) -> SkyView { SkyView() }
        func updateUIView(_ view: SkyView, context: Context) { (view.layer as! CfSkyLayer).appearance = appearance }
    }

    private final class SkyView: UIView {
        override class var layerClass: AnyClass { CfSkyLayer.self }
    }
#else
    import AppKit

    private struct NativeSky: NSViewRepresentable {
        let appearance: TokenAppearance
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer = CfSkyLayer()
            return view
        }
        func updateNSView(_ view: NSView, context: Context) { (view.layer as! CfSkyLayer).appearance = appearance }
    }
#endif
