# Working in this repo

NoSleep is a menu bar app that switches `pmset disablesleep`, so a Mac keeps
running with its lid closed. Swift 6 toolchain, language mode 5, macOS 14+,
SPM only. There is no `.xcodeproj` and there should not be one.

## Commands

```sh
make run       # debug build → .build/NoSleep.app → relaunch it
make test      # swift test
make verify    # debug app against the real system: sudo rule, timer, quit, crash backstop, energy
make verify-lid  # the lid test: close the lid when it asks
make release   # universal build → dist/NoSleep.dmg, cask in ../homebrew-tap updated
```

`NOSLEEP_SNAPSHOT_DIR=/tmp/nosleep .build/NoSleep.app/Contents/MacOS/NoSleep`
(debug build) renders the panel in every state, light and dark, to PNGs and
exits. Use it after touching `PanelView` rather than clicking through the menu
bar. A window flickers in the bottom-left corner while it runs, because Liquid
Glass only renders on screen; drawing the view into a bitmap leaves the glass out.

Building needs full Xcode, not just the Command Line Tools: `actool` compiles
`Resources/AppIcon.icon` (an Icon Composer bundle) into the Liquid Glass icon.

## Layout

```
Sources/NoSleepCore   the sleep switch, the battery, the stop rules. No UI.
Sources/NoSleep       the menu bar app: Controller (state), PanelView, app delegate
Resources/AppIcon.icon  the icon: one cat layer, colour and glass in icon.json
Scripts/              bundle.sh, release.sh, make-icon.swift (`make icon` redraws the cat layer)
install.sh            the curl | bash installer, served from main
```

The Homebrew cask lives in a separate repo, `../homebrew-tap`
(`intuito-studio/homebrew-tap`), so the install line is
`brew install --cask intuito-studio/tap/nosleep`.

## Things that are easy to break

**`SleepDisabled` outlives the process.** If the app dies holding sleep off, the
Mac never sleeps again. That is why there is a restore in
`applicationWillTerminate`, why SIGTERM is routed through a normal quit, and why
the battery stop is on by default. Keep all three.

**The backstop is the same binary.** launchd runs
`NoSleep.app/Contents/MacOS/NoSleep --backstop` every minute (`Backstop.swift`,
agent written at each launch). It reads the same defaults as the app, through
the keys in `StateKey`. Renaming one strands whatever an older build left.

**Never prompt from the background.** The timer and the battery stop run
unattended, often with the lid shut. Only a click may raise the password dialog.

**The sudoers rule is the whole privilege story.** It names exact commands with
exact arguments. Adding a command means adding it to `SleepSwitch.rule`. Old
installs get the new rule through the `.needsAccess` path, which asks for the
password once more. A rule that fails to parse breaks sudo for the whole Mac,
which is why it goes through `visudo -c` before it is installed.

**Distribution is unsigned by design.** No Developer ID, so no notarisation.
Builds are always signed ad hoc. The cask strips quarantine in
`postflight_steps`, which is the Homebrew 7 form; plain `postflight` is
deprecated there.

**Corners are concentric.** MenuBarExtra's window has a ~7 pt corner drawn
by the window server, far too tight around 18 pt tiles, so the app doesn't use
MenuBarExtra: `StatusPanel` is an NSStatusItem with a clear borderless panel,
and `PanelView` draws the only outer shape: sheet radius = tile radius + the
10 pt gap (`GlassTile`). Change one, change the other.
`NOSLEEP_PANEL_PROBE=<dir>` (debug build) opens the real panel at launch and
writes a capture of it there.

**The cat is paths** in `CatGlyph.swift` (230 × 200 grid): pointed ears and cheek
points, eyes closed curves when asleep, open with slit pupils when awake. Both
menu bar images are templates; colour on the grey menu bar cost contrast. The
panel badge is brown with yellow eyes when awake. `make icon` compiles
CatGlyph.swift on its own and redraws the icon's head and eyes layers.

**The panel is the system's own UI.** Liquid Glass tiles (`glassEffect`), the
native `Slider` and `Toggle`, the `.glass` button style. Don't draw custom
controls or use gradients. Everything glass sits behind an `if #available(macOS 26, *)`
with a plain fallback, because the app still runs on macOS 14.

## House rules

Build the current requirement, and only it. Comments say why, not what. Tests
state the rule they protect, in a sentence that reads well in a failure log.
