#if os(iOS)
    import SwiftUI
    import UIKit

    struct TripWindowSizeHost: UIViewRepresentable {
        let willChange: () -> Void
        let onChange: (CGSize) -> Void

        func makeUIView(context: Context) -> SizeProbe { SizeProbe(willChange: willChange, onChange: onChange) }
        func updateUIView(_ view: SizeProbe, context: Context) { view.reportSize() }

        final class SizeProbe: UIView {
            private let onChange: (CGSize) -> Void
            private let willChange: () -> Void
            private var reportedSize: CGSize?

            init(willChange: @escaping () -> Void, onChange: @escaping (CGSize) -> Void) {
                self.willChange = willChange
                self.onChange = onChange
                super.init(frame: .zero)
                isUserInteractionEnabled = false
            }

            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                reportSize()
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                reportSize()
            }

            func reportSize() {
                // The native tab rail consumes container width; the breakpoint is in window points.
                guard let size = window?.bounds.size, size != reportedSize else { return }
                if reportedSize != nil { willChange() }
                reportedSize = size
                DispatchQueue.main.async { [weak self] in self?.onChange(size) }
            }
        }
    }
#endif
