import Foundation
import Testing
@testable import SViewCore

struct MemoTests {
    private let text = """
        # poc-a

        - first capture

        ![poc-a-00](poc-a-00.png)

        - second capture, café

        ![poc-a-01](poc-a-01.png)
        ![poc-a-02](poc-a-02.png)
        """

    @Test func findsTheMemoNamedAfterTheFolder() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("poc-a")
        #expect(Memo.url(for: folder) == nil)
        try temp.file("poc-a/poc-a.md")
        #expect(Memo.url(for: folder)?.lastPathComponent == "poc-a.md")
    }

    @Test func highlightsTheReferenceAndItsBullet() {
        let string = text as NSString
        let first = Memo.highlights(for: "poc-a-00.png", in: text)
        #expect(first.map { string.substring(with: $0) } == ["- first capture\n\n![poc-a-00](poc-a-00.png)"])
        let second = Memo.highlights(for: "poc-a-01.png", in: text)
        #expect(second.map { string.substring(with: $0) } == ["- second capture, café\n\n![poc-a-01](poc-a-01.png)"])
        // A reference right under another one has no bullet of its own.
        let third = Memo.highlights(for: "poc-a-02.png", in: text)
        #expect(third.map { string.substring(with: $0) } == ["![poc-a-02](poc-a-02.png)"])
    }

    @Test func nothingForUnknownOrEmptyNames() {
        #expect(Memo.highlights(for: "other.png", in: text).isEmpty)
        #expect(Memo.highlights(for: "", in: text).isEmpty)
    }
}
