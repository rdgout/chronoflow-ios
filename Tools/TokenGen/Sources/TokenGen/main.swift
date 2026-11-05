import Foundation
import TokenGenCore

let root = URL(filePath: FileManager.default.currentDirectoryPath)
do {
    let outputs = try tokenOutputs(root: root)
    try writeOutputs(outputs, root: root, check: CommandLine.arguments.contains("--check"))
    print(
        "TokenGen: \(outputs.count) outputs verified\(CommandLine.arguments.contains("--check") ? "" : " and written")."
    )
} catch {
    FileHandle.standardError.write(Data("TokenGen: \(error)\n".utf8))
    exit(1)
}
