// SPDX-License-Identifier: AGPL-3.0-or-later
import Testing

@testable import CrosswindKit

@Test func usSourcesMapToUS() {
    #expect(KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.US") == .us)
    #expect(KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.ABC") == .us)
}

@Test func europeanLayoutsMapToXkbNames() {
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.German") == XkbLayout(layout: "de", variant: ""))
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.French") == XkbLayout(layout: "fr", variant: ""))
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.British") == XkbLayout(layout: "gb", variant: ""))
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.SwissFrench")
            == XkbLayout(layout: "ch", variant: "fr"))
}

@Test func simplificationVariantsUseTheirVariant() {
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.Dvorak")
            == XkbLayout(layout: "us", variant: "dvorak"))
    #expect(
        KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.keylayout.Colemak")
            == XkbLayout(layout: "us", variant: "colemak"))
}

@Test func unknownSourcesFallBackToUS() {
    #expect(KeyboardLayoutMap.xkb(forInputSourceID: "com.apple.inputmethod.SCIM.ITABC") == .us)
    #expect(KeyboardLayoutMap.xkb(forInputSourceID: "") == .us)
}
