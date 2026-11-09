import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor func planSnapshots<State: RawRepresentable, Content: View>(
    _ suite: String, states: [State], file: StaticString = #filePath,
    content: (State) throws -> Content
) async throws where State.RawValue == String {
    try await AuthTestHost.registerFonts()
    for fixture in try AuthDeviceFixture.all() where ["17e", "se", "duo"].contains(fixture.name) {
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        let variants: [(UIUserInterfaceStyle, String, UIContentSizeCategory)] =
            [UIUserInterfaceStyle.light, .dark].flatMap { style in ["en", "nl"].map { (style, $0, .large) } }
            + [(.light, "en", .extraExtraLarge)]
        for (style, language, size) in variants {
            for state in states {
                host.configure(try content(state), style: style, language: language, category: size)
                try await host.settle()
                let name =
                    "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(size.rawValue)-\(state.rawValue)"
                let reference = URL(filePath: "\(file)").deletingLastPathComponent()
                    .appending(path: "__Snapshots__/Plan/\(suite)/\(name).png")
                let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                let failure = try SnapshotReference.verify(
                    png: XCTUnwrap(host.image().pngData()), reference: reference, record: record)
                if record {
                    XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
                } else if let failure {
                    XCTFail(failure)
                }
            }
        }
    }
}
