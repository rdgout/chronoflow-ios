#if os(iOS)
    import SwiftUI
    import UIKit

    struct TripWindowSizeHost: UIViewRepresentable {
        let onChange: (CGSize) -> Void

        func makeUIView(context: Context) -> SizeProbe { SizeProbe(onChange: onChange) }
        func updateUIView(_ view: SizeProbe, context: Context) { view.reportSize() }

        final class SizeProbe: UIView {
            private let onChange: (CGSize) -> Void
            private var reportedSize: CGSize?

            init(onChange: @escaping (CGSize) -> Void) {
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
                reportedSize = size
                DispatchQueue.main.async { [weak self] in self?.onChange(size) }
            }
        }
    }
#endif
