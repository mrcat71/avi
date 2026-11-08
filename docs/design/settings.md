# Settings

The Settings window follows Rex's settings: a sidebar of colored icon tiles in
groups with Search Settings at the top, Back and Forward beside the section's
title, and the settings in flat cards under bold group titles, each control at
the end of its row. The sheets use the same cards and buttons; see
[Popups and notices](popups.md). The code is in `Sources/AppUI/Settings/`.

## Window

- `SettingsRoot` is a `NavigationSplitView`. `SettingsSection.sidebarGroups`
  orders the sidebar and splits it into groups. General leads on its own,
  drawn larger with Avi's icon and version.
- Search Settings keeps the sections whose title, `keywords`, and
  `advancedKeywords` hold every word of the query, ignoring case, accents, and
  hyphens. Add a new row's label to `keywords`, or to `advancedKeywords` when
  it sits under Advanced, or the search will not find it.
- `SettingsHistory` keeps Back and Forward, also Cmd-[ and Cmd-]. Clicking a
  section, Return in the search field, and `SettingsNavigation.shared.requested`
  all go through `visit`, so Back returns from each of them.
- SwiftUI gives the Settings window the preference toolbar, with the title
  above the toolbar's buttons, and `windowToolbarStyle` does not change it.
  `SettingsRoot` switches its window to the unified toolbar, so Back, Forward,
  and the title share one line.

## Advanced

Each section shows what most people change. The rest, such as AI's
temperature and prompts, Git's signing and pull request title rules, or tool
paths, goes in `SettingsAdvancedSection(.section) { groups }` at the end of
the section: a row titled Advanced with `advancedSummary` under it, closed
until clicked. The open state is kept per section in user defaults
(`avi.settings.showAdvanced.<section>`). A search whose words match only the
section's `advancedKeywords` opens it on the way in (`revealsAdvanced(for:)`).

A setting belongs under Advanced when leaving it alone is right for nearly
everyone and changing it needs to know how Avi or Git works. Never hide a
setting there that a problem needs you to see, such as a broken config file:
General shows that above everything. A section with nothing advanced has no
Advanced row; give it `advancedKeywords` and an `advancedSummary` together,
which a test checks.

## Rows

| Need | Component |
| --- | --- |
| A card of rows under a title | `SettingsGroup("Title")`, rows split by `SettingsDivider()` |
| A setting with its control at the end of the row | `SettingsFormRow(label, description:)` |
| A wide control under its label, such as a text editor | `SettingsFormRow(..., layout: .stacked)` |
| A status or a field under the row, such as an install state | `SettingsFormRow(...) { control } detail: { status }`; the detail takes the row's width and the control stays centered on the label |
| A note under a card, or a button beside its title | `SettingsGroup("Title", footer: "…") { rows } accessory: { button }` |
| A choice among a few values, with dividers or a Choose… action | `SettingsPopupMenu(label, selection:, items:)`, the sheets' flat pill, never a system pop-up |
| A one-line text or secret | `SettingsTextField(label, text:, prompt:, monospaced:, isSecure:)` |
| A few words of status with a symbol | `SettingsStatus(text, tone:)` |
| A card about one thing: Avi, a CLI, the config file | `SettingsHeroRow` first, the rows under it with `.settingsHeroIndent()` and `SettingsDivider(underHero: true)` |
| A sidebar or hero icon | `SettingsIcon(symbol:tint:)`, `SettingsAppIcon` |

Buttons in a section get `AviPopupButtonStyle(size: .small)`: gray pills,
red-tinted with red text for a destructive role. On/off settings are
switches, never checkboxes. `SettingsGroup` applies `SettingsSwitchStyle` to
every toggle: a 30 x 18 pt capsule with a 14 pt circular thumb, an accent-colored
on state, and a neutral off state. The controls stay at the right of their rows.
The shared style includes disabled and keyboard-focus states and respects Reduce
Motion. Keep each toggle's descriptive label even with `.labelsHidden()` so
assistive technology can identify it. Do not override the style in sections.

## Screenshots

`--render-screens` opens the Settings window itself for each section, so the
captures have its sidebar, search field, and toolbar. Panel names are
`settings-<section>`:

```sh
swift run AviApp --render-screens /tmp/avi-screens --only settings-general,settings-git
```

A section with Advanced settings is captured twice: `settings-<section>` with
them closed and `settings-<section>-advanced` with them open, in a taller
window.

The harness runs in the background and never takes focus, so the window draws
as inactive, with a dimmed title and toolbar buttons. Development builds have
no app icon, so General shows its gear tile where the packaged app shows
Avi's icon.
