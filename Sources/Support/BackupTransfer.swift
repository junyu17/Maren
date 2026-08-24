import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The document type used by the system file importer/exporter.
///
/// The extension is intentionally Maren-specific so an exported file is easy
/// to recognize and is not confused with a generic JSON document.  The
/// document contains only the encrypted envelope bytes; plaintext snapshots
/// are never written to disk by this layer.
extension UTType {
    static var marenBackup: UTType {
        UTType(exportedAs: "cd.cc.vela.encrypted-backup", conformingTo: .data)
    }
}

struct MarenBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.marenBackup]
    static let writableContentTypes: [UTType] = [.marenBackup]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupTransferError.invalidDocument
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupTransferError: Error, LocalizedError, Equatable {
    case invalidDocument
    case fileTooLarge
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "This file is not a valid Maren backup document."
        case .fileTooLarge:
            return "This backup is larger than the supported limit."
        case .fileReadFailed:
            return "The backup file could not be read."
        }
    }
}

/// File-system operations kept separate from the SwiftUI view for testing and
/// for one audited place where imported file limits are enforced.
enum BackupTransfer {
    static let maximumEncryptedFileSize = BackupLimits.standard.maxEncryptedBytes

    /// Reads an encrypted backup after checking that the security-scoped URL
    /// is a regular file and is within the encrypted-file cap.  The size check
    /// occurs before loading any bytes into memory.
    static func readEncryptedBackup(from url: URL,
                                    maximumBytes: Int = maximumEncryptedFileSize) throws -> Data {
        guard maximumBytes > 0 else { throw BackupTransferError.fileTooLarge }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw BackupTransferError.fileReadFailed
        }

        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumBytes else {
            throw BackupTransferError.fileTooLarge
        }

        let contents: Data
        do {
            contents = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BackupTransferError.fileReadFailed
        }
        guard contents.count <= maximumBytes else {
            throw BackupTransferError.fileTooLarge
        }
        return contents
    }
}
