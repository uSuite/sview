import Foundation

/// The PoC memo beside the captures (SV-402): `<folder>/<folder-name>.md`,
/// a heading, then for each capture a `- description` bullet above its
/// `![...](<capture>.png)` line.
public enum Memo {
    public static func url(for folder: URL) -> URL? {
        let url = folder.appendingPathComponent(folder.lastPathComponent + ".md")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// UTF-16 ranges (for text views) of the lines that mention `fileName`,
    /// each with the bullet line just above it, which describes the capture.
    public static func highlights(
        for fileName: String,
        in text: String
    ) -> [NSRange] {
        guard !fileName.isEmpty else {
            return []
        }
        let string = text as NSString
        var lines: [NSRange] = []
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, _ in
            lines.append(range)
        }
        var result: [NSRange] = []
        for (index, line) in lines.enumerated() where string.substring(with: line).contains(fileName) {
            var start = line
            var above = index - 1
            while above >= 0, string.substring(with: lines[above]).trimmingCharacters(in: .whitespaces).isEmpty {
                above -= 1
            }
            let bullet = above >= 0 ? string.substring(with: lines[above]).trimmingCharacters(in: .whitespaces) : ""
            if bullet.hasPrefix("- ") || bullet.hasPrefix("* ") {
                start = lines[above]
            }
            result.append(NSRange(location: start.location, length: NSMaxRange(line) - start.location))
        }
        return result
    }
}
