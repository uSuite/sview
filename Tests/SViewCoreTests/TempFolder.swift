import Foundation

/// A throwaway directory under the system temp folder, removed on deinit.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sview-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(
        _ path: String,
        bytes: Int = 1,
        modified: Date? = nil
    ) throws -> URL {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: bytes).write(to: fileURL)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified],
                ofItemAtPath: fileURL.path
            )
        }
        return fileURL
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folderURL = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        return folderURL
    }
}
