import Testing
@testable import SViewCore

struct NavigatorTests {
    @Test func emptyHasNoPosition() {
        var nav = Navigator(count: 0)
        #expect(nav.index == nil)
        #expect(nav.position == nil)
        let moved1 = nav.move(by: 1)
        #expect(!moved1)
        let moved2 = nav.first()
        #expect(!moved2)
        let moved3 = nav.go(to: 3)
        #expect(!moved3)
    }

    @Test func clampsWithoutWrap() {
        var nav = Navigator(count: 5)
        #expect(nav.isAtFirst)
        let moved4 = nav.move(by: -1)
        #expect(!moved4)
        let moved5 = nav.move(by: 3)
        #expect(moved5)
        #expect(nav.position == 4)
        let moved6 = nav.move(by: 10)
        #expect(moved6)
        #expect(nav.index == 4)
        #expect(nav.isAtLast)
        let moved7 = nav.move(by: 1)
        #expect(!moved7)
    }

    @Test func wrapsBothWays() {
        var nav = Navigator(count: 5, wraps: true)
        nav.move(by: -1)
        #expect(nav.index == 4)
        nav.move(by: 1)
        #expect(nav.index == 0)
        nav.move(by: 12)
        #expect(nav.index == 2)
        nav.move(by: -8)
        #expect(nav.index == 4)
    }

    @Test func firstLastAndGoTo() {
        var nav = Navigator(count: 30, index: 7)
        let moved8 = nav.last()
        #expect(moved8)
        #expect(nav.index == 29)
        let moved9 = nav.first()
        #expect(moved9)
        #expect(nav.index == 0)
        let moved10 = nav.go(to: 20)
        #expect(moved10)
        #expect(nav.index == 19)
        nav.go(to: 999)
        #expect(nav.index == 29)
        nav.go(to: -4)
        #expect(nav.index == 0)
    }

    @Test func initClampsAndResetKeepsIndex() {
        var nav = Navigator(count: 3, index: 9)
        #expect(nav.index == 2)
        nav.reset(count: 10, index: 6)
        #expect(nav.index == 6)
        nav.reset(count: 4, index: 6)
        #expect(nav.index == 3)
        nav.reset(count: 0, index: 1)
        #expect(nav.index == nil)
        nav.reset(count: 2, index: nil)
        #expect(nav.index == 0)
    }
}
