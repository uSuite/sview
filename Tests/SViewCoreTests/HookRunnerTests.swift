import Foundation
import Testing
@testable import SViewCore

struct HookRunnerTests {
    @Test func passesFileFolderAndMarkedAsEnvironment() async throws {
        let temp = try TempFolder()
        let file = try temp.file("a b; rm -rf.png")
        let other = try temp.file("c.png")
        let result = await HookRunner.run(
            #"printf '%s|%s|%s|' "$(basename "$FILE")" "$(basename "$FOLDER")" "$MARKED" ; pwd"#,
            file: file,
            folder: temp.url,
            marked: [file, other]
        )
        #expect(result.status == 0)
        #expect(!result.timedOut)
        let parts = result.output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        #expect(parts[0] == "a b; rm -rf.png")
        #expect(parts[1] == temp.url.lastPathComponent)
        #expect(parts[2] == "\(file.path)\n\(other.path)")
        #expect(parts[3].trimmingCharacters(in: .newlines).hasSuffix(temp.url.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func reportsStatusAndStderr() async {
        let result = await HookRunner.run("echo oops >&2; exit 3", file: nil, folder: nil, marked: [])
        #expect(result.status == 3)
        #expect(result.output == "oops\n")
    }

    @Test func timesOut() async {
        let result = await HookRunner.run("sleep 5", file: nil, folder: nil, marked: [], timeout: .milliseconds(200))
        #expect(result.timedOut)
        #expect(result.status != 0)
    }

    @Test func capsOutput() async {
        let result = await HookRunner.run("head -c 600000 /dev/zero | tr '\\0' x", file: nil, folder: nil, marked: [])
        #expect(result.output.hasSuffix("[output cut at 512 KB]"))
    }
}
