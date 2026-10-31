// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing
@testable import Crosswind

@Test func sidebarSectionsAreInOrder() {
    #expect(StoreSection.allCases.map(\.rawValue) == ["Discover", "Installed", "Updates"])
}
