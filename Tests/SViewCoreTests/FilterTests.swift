import Foundation
import Testing
@testable import SViewCore

struct FilterTests {
    @Test func emptyMatchesAll() {
        let filter = Filter("")
        #expect(filter.isEmpty)
        #expect(filter.matches("anything"))
    }

    @Test func substringIsSmartCase() {
        #expect(Filter("vm").matches("poc-VM-stop.png"))
        #expect(!Filter("VM").matches("poc-vm-stop.png"))
        #expect(Filter("VM").matches("poc-VM-stop.png"))
        #expect(!Filter("vm").isRegex)
    }

    @Test func regexWhenMetacharactersCompile() {
        let filter = Filter("-0[1-3]\\.png$")
        #expect(filter.isRegex)
        #expect(filter.matches("case-02.png"))
        #expect(!filter.matches("case-04.png"))
        #expect(!filter.matches("case-02.png.bak"))
    }

    @Test func invalidRegexFallsBackToSubstring() {
        let filter = Filter("a[b")
        #expect(!filter.isRegex)
        #expect(filter.matches("xa[by"))
        #expect(!filter.matches("ab"))
    }

    @Test func appliesToItems() {
        let items = ["a-01.png", "b-01.png", "a-02.png"].map {
            ImageItem(
                url: URL(fileURLWithPath: "/f/\($0)"),
                size: 0,
                modified: .distantPast,
                typeIdentifier: "public.png"
            )
        }
        #expect(Filter("a-").apply(to: items).map(\.name) == ["a-01.png", "a-02.png"])
        #expect(Filter("").apply(to: items).count == 3)
    }
}
