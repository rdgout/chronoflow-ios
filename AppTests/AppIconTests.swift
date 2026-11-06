import UIKit
import XCTest

nonisolated final class AppIconTests: XCTestCase {
    @MainActor
    func testBuiltAppDeclaresThePrimaryAppIcon() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "ChronoFlow")
        let names = try XCTUnwrap(primary["CFBundleIconFiles"] as? [String])
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let image = try XCTUnwrap(UIImage(named: name, in: .main, compatibleWith: nil))
            XCTAssertGreaterThan(try XCTUnwrap(image.cgImage).width, 0)
        }
        XCTAssertNil(Bundle.main.infoDictionary?["UIDesignRequiresCompatibility"])
    }

    func testCompiledCatalogContainsTheDesignedAppearanceRenditions() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Assets", withExtension: "car"))
        let catalog = try Data(contentsOf: url)
        for filename in ["AppIcon-default.png", "AppIcon-dark.png", "AppIcon-tinted.png"] {
            XCTAssertNotNil(catalog.range(of: Data(filename.utf8)), "Missing compiled rendition: \(filename)")
        }
        for appearance in ["UIAppearanceDark", "ISAppearanceTintable"] {
            XCTAssertNotNil(catalog.range(of: Data(appearance.utf8)), "Missing compiled appearance: \(appearance)")
        }
        XCTAssertNotNil(catalog.range(of: Data("ChronoFlow.iconstack".utf8)), "Missing compiled Liquid Glass stack")
    }
}
