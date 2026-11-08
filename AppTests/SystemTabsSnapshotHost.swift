import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor final class SystemTabsSnapshotHost {
    let container: SnapshotContainer
    let controller: UIHostingController<AnyView>
    let fixture: AuthDeviceFixture
    var tabController: UITabBarController? { findTabController(in: controller) }

    init<V: View>(_ view: V, fixture: AuthDeviceFixture, variant: PlanSnapshotVariant) {
        self.fixture = fixture
        container = SnapshotContainer(
            size: fixture.size,
            insets: .init(
                top: fixture.insets.top, left: fixture.insets.left,
                bottom: fixture.insets.bottom, right: fixture.insets.right),
            scale: fixture.scale, nativeSafeArea: true)
        container.window.overrideUserInterfaceStyle = variant.style
        container.window.traitOverrides.preferredContentSizeCategory = variant.category
        container.root.traitOverrides.horizontalSizeClass = .compact
        container.root.traitOverrides.verticalSizeClass = .regular
        ContentSizeCap.apply(to: container.root, in: container.window)
        controller = UIHostingController(
            rootView: AnyView(
                view.environment(\.locale, Locale(identifier: variant.language))
                    .environment(\.displayScale, fixture.scale)
                    .environment(\.colorScheme, variant.style == .dark ? .dark : .light)))
        container.host(controller)
    }

    func capture(selectedIndex: Int, contentIdentifier: String? = nil) async throws -> UIImage {
        let deadline = ContinuousClock.now + .seconds(5)
        var selectedAt: ContinuousClock.Instant?
        var previousFrame: CGRect?
        var matches = 0
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            layout()
            guard let tabs = tabController, tabs.viewControllers?.count == 3 else { continue }
            if selectedAt == nil {
                UIView.performWithoutAnimation {
                    tabs.selectedIndex = selectedIndex
                    if let selected = tabs.selectedViewController {
                        tabs.delegate?.tabBarController?(tabs, didSelect: selected)
                    }
                }
                selectedAt = .now
                continue
            }
            guard let selectedAt, ContinuousClock.now - selectedAt >= .milliseconds(500),
                contentIdentifier.map({ containsIdentifier($0, in: controller.view) }) ?? true
            else { continue }
            let bar = try requireTabBar(selectedIndex: selectedIndex)
            let frame = bar.convert(bar.bounds, to: container.window)
            matches = frame == previousFrame ? matches + 1 : 0
            previousFrame = frame
            guard matches >= 2 else { continue }
            let image = try hierarchyImage()
            try validate(image, selectedIndex: selectedIndex)
            return image
        }
        throw CaptureFailure.invalid(
            "System tabs or \(contentIdentifier ?? "selected tab") did not lay out within 5 seconds")
    }

    func requireTabBar(selectedIndex: Int) throws -> UITabBar {
        let window = container.window
        guard let tabs = tabController else {
            throw CaptureFailure.invalid("Missing system UITabBarController")
        }
        let bar = tabs.tabBar
        guard let items = bar.items else { throw CaptureFailure.invalid("Missing system tab items") }
        guard items.count == 3, tabs.viewControllers?.count == 3,
            items.indices.contains(selectedIndex), tabs.selectedIndex == selectedIndex,
            bar.selectedItem === items[selectedIndex], items.allSatisfy({ $0.image?.isSymbolImage == true })
        else { throw CaptureFailure.invalid("Expected three symbol tabs with item \(selectedIndex) selected") }
        var ancestor: UIView? = bar
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0 else {
                throw CaptureFailure.invalid("System tab bar is hidden")
            }
            ancestor = view.superview
        }
        let frame = bar.convert(bar.bounds, to: window)
        guard window.isKeyWindow, bar.window === window, !frame.isEmpty, window.bounds.contains(frame) else {
            throw CaptureFailure.invalid("System tab bar is detached or outside the capture")
        }
        guard window.bounds.size == fixture.size, controller.view.bounds.size == fixture.size,
            window.safeAreaInsets == fixture.insets, controller.view.safeAreaInsets == fixture.insets,
            controller.traitCollection.displayScale == fixture.scale,
            controller.traitCollection.horizontalSizeClass == .compact,
            controller.traitCollection.verticalSizeClass == .regular
        else { throw CaptureFailure.invalid("System tabs do not match the profile's bounds, insets or traits") }
        return bar
    }

    func validate(_ image: UIImage, selectedIndex: Int) throws {
        let bar = try requireTabBar(selectedIndex: selectedIndex)
        let raster = try SnapshotRaster(image: XCTUnwrap(image.cgImage))
        let frame = bar.convert(bar.bounds, to: container.window)
        guard raster.width == Int(fixture.size.width * fixture.scale),
            raster.height == Int(fixture.size.height * fixture.scale),
            AuthSnapshotCapture.hasInk(raster, in: frame, scale: fixture.scale)
        else { throw CaptureFailure.invalid("Capture omits the system tab bar or uses the wrong dimensions") }
    }

    private func hierarchyImage() throws -> UIImage {
        layout()
        let window = container.window
        let format = UIGraphicsImageRendererFormat()
        format.scale = fixture.scale
        format.opaque = false
        format.preferredRange = .standard
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard rendered else { throw CaptureFailure.invalid("drawHierarchy failed; refusing to record") }
        return image
    }

    private func layout() {
        UIView.performWithoutAnimation {
            @MainActor func layoutTree(_ view: UIView) {
                view.layoutIfNeeded()
                view.subviews.forEach(layoutTree)
            }
            layoutTree(container.window)
            CATransaction.flush()
        }
    }

    private func findTabController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        return controller.children.lazy.compactMap { self.findTabController(in: $0) }.first
    }

    private func containsIdentifier(_ identifier: String, in element: NSObject) -> Bool {
        var visited: Set<ObjectIdentifier> = []
        @MainActor func contains(_ element: NSObject) -> Bool {
            guard visited.insert(ObjectIdentifier(element)).inserted else { return false }
            if (element as? any UIAccessibilityIdentification)?.accessibilityIdentifier == identifier { return true }
            if let view = element as? UIView, view.subviews.contains(where: { contains($0) }) { return true }
            if let elements = element.accessibilityElements {
                return elements.compactMap { $0 as? NSObject }.contains(where: contains)
            }
            let count = element.accessibilityElementCount()
            guard count > 0, count != NSNotFound else { return false }
            return (0..<count).contains { index in
                (element.accessibilityElement(at: index) as? NSObject).map(contains) ?? false
            }
        }
        return contains(element)
    }

    func close() { container.close() }

    private enum CaptureFailure: Error { case invalid(String) }
}
