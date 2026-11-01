# Accessibility and localization

Status of the accessibility and localization pass over the store UI (`App/Store`), the stub
(`App/Stub`) and the host status item (`App/Host/StatusItem.swift`). Checked by code review and a
clean Debug build. Not checked with VoiceOver or the other system settings; that needs the manual
steps at the end.

## What was changed

**VoiceOver and labels**

- Cards and rows (`AppCard`, `AppRow`, hero card) combine their text into one element, so VoiceOver
  reads the name and summary together. The action button stays a separate control.
- Verified publisher seal: label and tooltip read "Verified developer", combined with the developer
  name.
- Progress ring during an operation: label "Working on <app>", value "<n> percent".
- Get, Open and Update buttons carry the app name in their label and tooltip.
- Compatibility rating badge is labelled "Compatibility: <rating>". The info button has a tooltip.
- Running indicator on the app page and in Installed is read as "Running".
- Remove-folder button in Shared Folders is labelled "Stop sharing <folder>" (it was icon-only).
- Memory slider exposes its value; the duplicate text beside it is hidden from VoiceOver.
- Diagnostics chart has a label. The Windows table and the log table keep their native column
  semantics.
- Skeleton placeholders on Discover are hidden from VoiceOver.
- Section and page titles use the header trait (Discover sections, app name, About, What's New,
  Information).
- Update count on the Updates sidebar item has an accessibility value.

**Keyboard**

- Return activates the primary action on the app page (`keyboardShortcut(.defaultAction)`).
- Escape closes the full-size screenshot sheet (`onExitCommand`), as well as Done.
- Menu commands (`App/Store/StoreCommands.swift`): Cmd-F focuses the search field, Cmd-1, Cmd-2 and
  Cmd-3 switch to Discover, Installed and Updates. They are disabled when no store window is focused.
- Tooltips (`.help`) added to icon-only and ambiguous controls: More menu, screenshot thumbnails,
  compatibility info, Show in Finder, log filter toggles and buttons, shared-folder remove.

**Motion, contrast, text size**

- "Show More" / "Show Less" toggles without the animated height change when Reduce Motion is on.
- No auto-advancing or looping animation exists in the store UI. The setup spinner is the system
  `ProgressView`.
- Colours are system colours (`.secondary`, `.tint`, `.green`, `.red`, `.orange`) and materials
  (`.quaternary`, `.regularMaterial`), so they follow Increase Contrast and Reduce Transparency.
- Text uses text styles (`.headline`, `.caption`, and so on). Fixed sizes remain only on decorative
  symbols and on the fixed-size screenshot frames.

**Localization**

- `App/Store/Resources/Localizable.xcstrings`, `App/Stub/Localizable.xcstrings` and
  `App/Host/Localizable.xcstrings` are String Catalogs (source language `en`). All three are in the
  Resources build phase of their target (`project.yml`).
- User-visible literals use `LocalizedStringKey` or `String(localized:)`, including the NSAlert and
  NSOpenPanel/NSSavePanel strings in the stub and the Shared Folders panel.
- Plural variations: "N apps can be updated", "N results", "N updates available".
- Data (app names, summaries, developer names, paths, file names, log text, versions, IDs) uses
  `Text(verbatim:)` so it is never looked up in the catalog.
- Each catalog key has a translator comment.
- Xcode did not write the catalogs during the CLI build (`SWIFT_EMIT_LOC_STRINGS` is set in
  `project.yml`, but extraction still did not run). The catalogs were written by hand from the
  inventory of literals. Re-extract in Xcode (Product > Build with Xcode, or Editor > Export
  Localizations) before adding a language, and diff the catalog for keys that are no longer used.

**Known gaps**

- Interpolated keys are written with format specifiers from the Swift source (`%@`, `%lld`). The
  catalog matches the source by hand, so a mismatch shows the key text rather than failing the build.
  The re-extraction above catches it.
- `Text(verbatim:)` on Flathub-provided text means translators cannot see those strings. That is
  intended: they are data.
- The guest error string "The file chooser failed on the Mac..." and the "not supported yet" reply
  are sent to the guest, not shown on the Mac. They stay in English.
- Cmd-F is set in the Edit menu after "Find". If `searchable` adds its own Find item, the two may
  appear together; check in the menu bar (manual step 5).
- The swift-format and SwiftLint checks pass on the files changed here. `App/Store/Updates/AppUpdater.swift`
  (not part of this pass) still has closure-parameter-position warnings.

## Manual VoiceOver and keyboard verification

These need a person with the system settings and VoiceOver turned on. Run each step on a build with
the Linux environment ready, so there is a catalog and at least one installed app.

Turn on VoiceOver with Cmd-F5. Use VO (Control-Option) keys for the steps below.

1. **Sidebar.** Tab into the sidebar. VO reads Discover, each category with its count, Installed and
   Updates. The Updates item reads its update count. The three section headers (Store, Categories,
   Library) are read as headings.
2. **Discover cards.** Move through the hero card and the Popular row. Each card reads once as
   "name, summary", not as separate text fragments. Its Get or Open button is a separate control with
   the app name in its label.
3. **Verified seal.** On an app with a verified publisher, the developer line reads
   "<developer>, Verified developer". On an app without one, nothing extra is read.
4. **Progress ring.** Click Get on an app. While it works, the ring reads "Working on <app>" with a
   percent value. Its tooltip shows the detail text.
5. **Menu bar commands.** Open the Window and Edit menus. Confirm "Find Apps" (Cmd-F), "Discover"
   (Cmd-1), "Installed" (Cmd-2) and "Updates" (Cmd-3) appear, and that Cmd-F focuses the toolbar
   search field. Note whether the Edit menu shows a second Find item.
6. **Search.** Cmd-F, type a query. Results appear under a "N results" header. Note whether Escape
   clears the query; the store does not handle it explicitly.
7. **App page.** Open an app. Confirm the name is read as a heading. Tab to Get, Open or Update and
   press Return: it activates the primary action.
8. **Compatibility.** Tab to the compatibility badge: it reads "Compatibility: <rating>". Tab to the
   info button, read its tooltip, press Space to open the popover, and check the explanation text
   reads correctly.
9. **Screenshots.** Tab to a screenshot, press Return. The sheet opens. Confirm the screenshot caption
   is read, then press Escape: the sheet closes and focus returns to the thumbnail. Repeat with
   Return on Done.
10. **Show More.** Turn on Reduce Motion (System Settings > Accessibility > Motion). Activate
    "Show More": the text expands without animation. Turn it off and confirm the snappy animation.
11. **Installed and updates.** On the Installed page, each row reads as "name, Version x, Running" when
    the app runs. The context menu offers Open, Show in Finder and Uninstall. On Updates, "Update All"
    is reachable by keyboard; its progress reads "Updating all apps".
12. **Settings.** Open Settings (Cmd-,). Tab through the General, Environment, Storage, Shared Folders
    and About tabs. Confirm the memory slider reads its value ("N GiB") and each shared folder's
    remove button reads "Stop sharing <folder>".
13. **Diagnostics.** Open Diagnostics (Cmd-Option-D). In the Logs tab, confirm the filter field,
    pickers and toggles read their labels. On the Windows tab, the latency chart reads
    "Input-to-frame latency chart".
14. **Contrast and transparency.** Turn on Increase Contrast and Reduce Transparency. Check the
    rating badges, the Running dot, the failure banner and the hero card remain readable.
15. **Dynamic Type.** Set the text size to the largest value (System Settings > Displays / Text).
    Check the sidebar, the card text, the app page header and the Settings forms do not clip or
    overlap. Fixed-size screenshot frames are expected to stay fixed.
16. **Menu bar item (host).** With the agent running, open its status item. Confirm "Crosswind Host" is
    the accessibility label and the menu reads "Linux environment: <state>", "Running Apps" and
    "Open Crosswind".
17. **Localization smoke test.** In the scheme, set the app language to a pseudo-language (for
    example Scheme > Run > Options > App Language > Double-Length Pseudolanguage). Confirm strings
    expand without clipping and the data values (app names, versions) are unchanged.
