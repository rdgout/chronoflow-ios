#if canImport(UIKit)
    import CoreTransferable
    import Foundation
    import UniformTypeIdentifiers

    struct SettingsRecoveryDocument: Transferable, Sendable {
        let text: String
        let name: String
        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
                .suggestedFileName { $0.name }
        }
    }
#endif
