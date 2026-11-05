import AssetGenCore
import Foundation
import TokenGenCore

let root = URL(filePath: FileManager.default.currentDirectoryPath)
do {
    let outputs = try assetOutputs(root: root)
    try writeOutputs(outputs, root: root, check: CommandLine.arguments.contains("--check"))
    print(
        "AssetGen: \(outputs.count) outputs verified\(CommandLine.arguments.contains("--check") ? "" : " and written")."
    )
} catch {
    FileHandle.standardError.write(Data("AssetGen: \(error)\n".utf8))
    exit(1)
}
