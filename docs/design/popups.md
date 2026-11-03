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
optional accessory), the content, and `AviPopupFooter`. Sheets that size
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
| A labelled control | `AviPopupField`, label above |
| A label over a control you lay out yourself | `AviPopupLabel` |
| On/off choices | `AviPopupOption` rows in an `AviPopupGroup`, split by `AviPopupGroupDivider` |
| One of a few choices | `AviPopupChoices`, in place of radio buttons |
| A warning before the click | `AviPopupCallout` |
| Small print under a control | `AviPopupNote` |
| Small print in the footer | `AviPopupFooterNote` |

Buttons are flat pills. They use `.aviProminent` for the action (red with a
destructive role) and `.aviSecondary` for Cancel and the rest (red-tinted
with red text for a destructive role). Keep `.keyboardShortcut(.cancelAction)`
on Cancel and `.defaultAction` on the action, except for destructive actions,
which are clicked, never confirmed with Return.

Confirmations (`.alert`, `.confirmationDialog`) stay system alerts: macOS
draws them in its current style and keeps their keyboard and VoiceOver
behavior.

## Screenshots

A debug build renders the notices and the sheets, presented as real sheets,
against demo repositories:

```sh
swift run AviApp --render-screens /tmp/avi-screens --only notices,notice-release-notes,popup-push,popup-merge
```

Panel names are in `ScreenshotHarness.swift`. The harness never starts the
agent socket, so the Avi you use keeps working. Captures need Screen
Recording permission for the terminal.
