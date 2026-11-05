# Popups and notices

Avi's sheets and transient messages share one look with Settings, after Rex:
floating cards with an icon, a short title, flat groups of rows, and pill
buttons in reach. The components live in `Sources/AppUI/Components/`; the
Settings side is in [Settings](settings.md).

## Notices

`AviNotice` is a card that floats at the top of a window's content, for
things that happen while you work. It never blocks the window. A notice that
needs an answer keeps its buttons until you choose; the others close with
their close button or after `autoDismiss`.

- App notices, such as the update's, go through `AviNoticeCenter.shared`.
  Only the window you work in shows them.
- A window's own notices come from its state: `WorkspaceSession.notices` and
  the repository's `errorMessage`, which `RepositoryView` turns into an error
  notice. Closing the notice clears the error.
- `.aviNotices(_:)` hosts them. `RepositoryView` puts them under the toolbar
  and the banners; Settings, File History, and the agent guide host the app
  notices.
- Notice buttons take no Return or Escape, so typing in the window never
  triggers them.
- `AviFloatingSurface` draws Liquid Glass on macOS 26 and later, a material
  card before that, and a solid card with Reduce Transparency. The command
  palette uses it too.

`ErrorNoticeText.split` turns an error message into a title and the rest:
`Could not save the patch: disk full` becomes the title and its reason. Long
messages fold to three lines behind **Show Full Message**.

## Updates

`UpdateNoticeDriver` is Sparkle's `SPUUserDriver`. Every step of an update is
the update notice instead of Sparkle's windows, and the driver answers
Sparkle's pending reply with the button you click. `UpdateNotice.make` maps
each `UpdatePhase` to a notice without Sparkle, so `UpdateNoticeTests` checks
every step. Release notes come from the feed's Markdown, parsed by
`ReleaseNotes` into headings and list items.

Development builds have no updater (`UpdateConfiguration`), so check the
steps with the screenshot harness below.

## Sheets

`AviPopup` frames a sheet: `AviPopupHeader` (icon tile, title, subtitle, an
optional accessory), the content, and `AviPopupFooter`. A sheet whose content
draws its own icons, such as Push, passes no `symbol` and its title stands
alone. Sheets that size
themselves, such as Compare or Interactive Rebase, use the header and footer
directly. The footer has no bar of its own; a sheet whose content scrolls up
to the buttons, such as the repository picker, uses
`AviPopupFooter(separated: true)` for a line above them.

Groups are flat cards in `DS.Palette.groupFill` with no outline, and the
lines between their rows stop short of both edges, in line with the text.
Labels are short titles in sentence case (`AviPopupLabel`); the uppercase
monospaced `aviLabel` belongs to the workspace's panel headers, not to sheets.

| Need | Component |
| --- | --- |
| A setting or value in a card: label on the left, control at the end, as in Settings | `AviPopupRow` in an `AviPopupGroup`; `.stacked` puts a wide control, such as a text field, under the label |
| A labelled control | `AviPopupField`, label above |
| A label over a control you lay out yourself | `AviPopupLabel` |
| On/off choices | `AviPopupOption` rows in an `AviPopupGroup`, split by `AviPopupGroupDivider` |
| One of a few choices | `AviPopupChoices`, in place of radio buttons |
| One value from a list, such as a remote or a branch | `AviPopupMenu`, a pill that opens the list as a menu |
| Text to type | `AviPopupTextField`, with an optional control at its end; `AviPopupTextEditor` for a few lines |
| A warning before the click | `AviPopupCallout` |
| Small print under a control | `AviPopupNote` |
| Small print in the footer | `AviPopupFooterNote` |

Don't use a `.menu` picker or a system text field in a sheet. The app
links against the macOS 14 SDK, so they draw in the old style, and a menu
picker with `.fixedSize()` grows to its longest option: the Push sheet's
**Into** list holds every branch on the remote, and one long name made the
sheet's content wider than its window, cut off on both sides.
`AviPopupMenu` hugs its value up to `maxWidth` and gives up the middle of a
longer one. Switches stay the system's in sheets: Settings' compact
`SettingsSwitchStyle` is focusable, so the first one in a sheet takes the
focus ring as the sheet opens.

Push shows its route in the first card: the branch, a line down to the
remote, and a badge for what the push does there (**New branch**, the commits
it sends, **Up to date**, or how far the remote is ahead, in orange, since a
plain push is then refused). The badge's tooltip says it in full.

Buttons are flat pills. They use `.aviProminent` for the action (red with a
destructive role) and `.aviSecondary` for Cancel and the rest (red-tinted
with red text for a destructive role). Put `.aviKeyboardShortcut(.cancelAction)`
on Cancel and `.aviKeyboardShortcut(.defaultAction)` on the action, except for
destructive actions, which are clicked, never confirmed with Return.

Use `aviKeyboardShortcut`, never `keyboardShortcut`, on a pill. SwiftUI draws
the pill itself, so its key is SwiftUI's to route, and a sheet presented from
inside a split view's pane, such as Push from the toolbar or a branch sheet
from the sidebar, gets it routed to the window behind the sheet: Return and
Escape did nothing there. `aviKeyboardShortcut` also puts the key on an
invisible AppKit button in the sheet's own window, as system buttons carry
theirs, so the key works wherever the sheet comes from. Return in a text
editor still adds a line, and Return in a text field confirms, as in any Mac
dialog.

Confirmations (`.alert`, `.confirmationDialog`) stay system alerts: macOS
draws them in its current style and keeps their keyboard and VoiceOver
behavior.

## Screenshots

A debug build renders the notices and the sheets, presented as real sheets,
against demo repositories:

```sh
swift run AviApp --render-screens /tmp/avi-screens --only notices,notice-release-notes,popup-push,popup-push-pr,popup-merge
```

`popup-push-pr` is Push at its tallest: a new branch with a pull request, on
a repository with two remotes and a remote branch named longer than the
sheet is wide.

Panel names are in `ScreenshotHarness.swift`. The harness never starts the
agent socket, so the Avi you use keeps working. Captures need Screen
Recording permission for the terminal.
