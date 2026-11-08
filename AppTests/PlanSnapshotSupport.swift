import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor struct PlanSnapshotVariant {
    let style: UIUserInterfaceStyle
    let language: String
    let category: UIContentSizeCategory

    static var all: [Self] {
        [UIUserInterfaceStyle.light, .dark].flatMap { style in
            ["en", "nl"].map { Self(style: style, language: $0, category: .large) }
        } + [Self(style: .light, language: "en", category: .extraExtraLarge)]
    }
}

@MainActor func planSnapshots<State: RawRepresentable, Content: View>(
    _ suite: String, states: [State], file: StaticString = #filePath,
    content: (State) throws -> Content
) async throws where State.RawValue == String {
    try await AuthTestHost.registerFonts()
    for fixture in try AuthDeviceFixture.all() where ["17e", "se", "duo"].contains(fixture.name) {
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        for variant in PlanSnapshotVariant.all {
            for state in states {
                host.configure(
                    try content(state), style: variant.style, language: variant.language, category: variant.category)
                try await host.settle()
                try verifyPlanSnapshot(
                    host.image(), suite: suite, state: state.rawValue, fixture: fixture, variant: variant, file: file)
            }
        }
    }
}

@MainActor func verifyPlanSnapshot(
    _ image: UIImage, suite: String, state: String, fixture: AuthDeviceFixture, variant: PlanSnapshotVariant,
    file: StaticString = #filePath
) throws {
    let name =
        "\(fixture.snapshotName)-\(variant.style == .dark ? "dark" : "light")-\(variant.language)-\(variant.category.rawValue)-\(state)"
    let reference = URL(filePath: "\(file)").deletingLastPathComponent()
        .appending(path: "__Snapshots__/Plan/\(suite)/\(name).png")
    let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    let failure = try SnapshotReference.verify(
        png: XCTUnwrap(image.pngData()), reference: reference, record: record)
    if record {
        XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
    } else if let failure {
        XCTFail(failure)
    }
}
