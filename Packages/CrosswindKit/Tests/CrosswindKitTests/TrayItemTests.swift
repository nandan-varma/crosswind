// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Testing

@testable import CrosswindKit

@Suite struct TrayItemTests {
    private func message(
        id: String = "org.example/StatusNotifierItem", width: UInt32 = 2, height: UInt32 = 1,
        rgba: Data = Data(count: 8), title: String = "Example"
    ) -> Crosswind_Control_TrayItemChanged {
        .with {
            $0.id = id
            $0.title = title
            $0.iconWidth = width
            $0.iconHeight = height
            $0.iconRgba = rgba
        }
    }

    @Test func aWellFormedIconIsAccepted() throws {
        let item = try #require(TrayItem(message()))
        #expect(item.icon?.width == 2)
        #expect(item.icon?.height == 1)
        #expect(item.title == "Example")
        #expect(!item.isPassive)
    }

    @Test func anItemWithoutPixelsHasNoIcon() throws {
        let item = try #require(TrayItem(message(width: 0, height: 0, rgba: Data())))
        #expect(item.icon == nil)
    }

    @Test func emptyOrOversizedIDsAreRefused() {
        #expect(TrayItem(message(id: "")) == nil)
        #expect(TrayItem(message(id: String(repeating: "a", count: TrayItem.maxIDBytes + 1))) == nil)
    }

    @Test func pixelDataMustMatchTheDeclaredSize() {
        #expect(TrayItem(message(rgba: Data(count: 7))) == nil)
        #expect(TrayItem(message(width: 0, height: 1, rgba: Data())) == nil)
    }

    @Test func iconsBeyondTheSideLimitAreRefused() {
        let side = UInt32(TrayItem.maxIconSide + 1)
        #expect(TrayItem(message(width: side, height: 1, rgba: Data(count: Int(side) * 4))) == nil)
    }

    @Test func longTitlesAreCutOnACharacterBoundary() throws {
        let title = String(repeating: "é", count: TrayItem.maxTitleBytes)
        let item = try #require(TrayItem(message(title: title)))
        #expect(item.title.utf8.count <= TrayItem.maxTitleBytes)
        #expect(item.title.allSatisfy { $0 == "é" })
    }
}

@Test func aTrayMenuIsCutToTheLevelAndEntryLimits() throws {
    func entry(_ id: Int32, _ children: [Crosswind_Control_TrayMenuItem] = []) -> Crosswind_Control_TrayMenuItem {
        .with {
            $0.id = id
            $0.label = "item \(id)"
            $0.enabled = true
            $0.children = children
        }
    }
    let deep = entry(1, [entry(2, [entry(3, [entry(4, [entry(5)])])])])
    let item = try #require(
        TrayItem(
            .with {
                $0.id = "a/b"
                $0.menu = [deep]
                $0.menuOnActivate = true
            }))
    #expect(item.menuOnActivate)
    #expect(item.menu[0].children[0].children[0].children[0].children.isEmpty)  // level 5 is dropped

    let many = (0..<500).map { entry(Int32($0)) }
    let wide = try #require(
        TrayItem(
            .with {
                $0.id = "a/b"
                $0.menu = many
            }))
    #expect(wide.menu.count == TrayItem.maxMenuEntries)
    let none = try #require(
        TrayItem(
            .with {
                $0.id = "a/b"
                $0.menuOnActivate = true
            }))
    #expect(!none.menuOnActivate)  // no menu to show
}
