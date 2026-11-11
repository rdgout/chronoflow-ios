import SwiftUI

// Reflow the same children: swapping ViewThatFits branches can dismiss a compact picker's popover.
struct WizardFlightRowLayout: Layout {
    let spacing: CGFloat
    var fillsWidth = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = layout.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        return arrangement(
            width: width, sizes: ideal,
            stackedSizes: subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) })
    }

    struct Arrangement {
        let size: CGSize
        let frames: [CGRect]
    }

    func arrangement(width: CGFloat?, sizes: [CGSize], stackedSizes: [CGSize]? = nil) -> Arrangement {
        let horizontal = sizes.reduce(0) { $0 + $1.width } + spacing <= (width ?? .infinity)
        let sizes = horizontal ? sizes : stackedSizes ?? sizes
        let usedWidth = horizontal ? sizes.reduce(0) { $0 + $1.width } + spacing : sizes.map(\.width).max() ?? 0
        let height = horizontal ? sizes.map(\.height).max() ?? 0 : sizes.reduce(0) { $0 + $1.height } + spacing
        let size = CGSize(width: fillsWidth ? width ?? usedWidth : usedWidth, height: height)
        var offset: CGFloat = 0
        let frames = sizes.enumerated().map { index, child in
            let x = horizontal ? (fillsWidth && index == sizes.count - 1 ? size.width - child.width : offset) : 0
            let y = horizontal ? (height - child.height) / 2 : offset
            offset += (horizontal ? child.width : child.height) + spacing
            return CGRect(origin: CGPoint(x: x, y: y), size: child)
        }
        return Arrangement(size: size, frames: frames)
    }
}
