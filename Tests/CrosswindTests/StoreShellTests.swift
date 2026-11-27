// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import Crosswind

@Test func sidebarSectionsAreDistinct() {
    let sections: Set<StoreSection> = [.discover, .installed, .updates]
    #expect(sections.count == 3)
}
