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

The lid effect (debug build) can be checked without closing the lid.
`NOSLEEP_LID_ANGLE=60` holds the hinge at 60°, `NOSLEEP_LID_SWEEP=1` closes it
110°→0°→110° every 16 s; either shows the overlay only while NoSleep is on.
`NOSLEEP_FOLD_PICTURE=<png>` folds that picture instead of a screen capture, so
no Screen Recording is needed, `NOSLEEP_LID_POINTER=x,y` holds the pointer at
that point (points from the built-in display's top-left), and
`NOSLEEP_CAT_FALLBACK=1` draws the macOS 14 cat. `NOSLEEP_LID_PROBE=<dir>` runs alone, beside a running NoSleep: it holds
98°, 84°, 66°, 40° and 10° in turn, writes `lid-<angle>.png` of the overlay
(over the fold picture) for each, and exits without the quit-time restore;
`NOSLEEP_LID_PROBE_ANGLES=24,18,10` holds those angles instead.

Building needs full Xcode, not just the Command Line Tools: `actool` compiles
`Resources/AppIcon.icon` (an Icon Composer bundle) into the Liquid Glass icon.

## Layout

```
Sources/NoSleepCore   the sleep switch, the battery, the stop rules, the lid sensor and its curves. No UI.
Sources/NoSleep       the menu bar app: Controller (state), PanelView, app delegate
Resources/AppIcon.icon  the icon: one cat layer, colour and glass in icon.json
Scripts/              bundle.sh, release.sh, make-icon.swift (`make icon` redraws the cat layer)
install.sh            the curl | bash installer, served from main
site/                 the home page: Next.js static export (`cd site && npm run dev`)
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

**The panel is for switching.** The full activity log lives in
`SettingsView`, an AppKit-owned window opened from the panel's Settings…
button. The SwiftUI scene is a `MenuBarExtra` that is never inserted: a
`Settings` scene there opened as an empty window at launch. Joining a network
is left to macOS (Wi-Fi → Ask to join hotspots → Automatic); an earlier
hotspot feature was removed.

**Updates are one click.** `Updater` reads the latest GitHub release once a
day, and its `NoSleep.dmg` asset is what gets installed: keep that asset name
and the `v<version>` tag. Update (in the panel, or the notification) downloads
it, swaps the bundle in place and relaunches, without undoing the session; the
new copy carries it on from the defaults. Debug builds only check when
`NOSLEEP_UPDATE_FEED` names a feed (a file:// JSON shaped like GitHub's works),
and `NOSLEEP_INSTALL_UPDATE=1` installs without the click.

**The lid overlay never gets in the way.** `LidEffect` reads the hinge
(`LidAngleSensor`, ~10 Hz, smoothed by `DampedSpring`) only while NoSleep is
on, and `LidOverlay` is a borderless window at the shielding level that
ignores clicks and can't become key. It is ordered out, its display link
stopped and the capture stream with it, when NoSleep turns off, above 100°,
when the built-in display goes away, and on quit. The cat's eyes follow the
pointer by reading `NSEvent.mouseLocation` at those same readings, never an
event monitor or tap, so they need no permission; with Reduce Motion on, or
the screen dark, they look ahead. The cat is drawn once and slid; only the
pupils redraw when the pointer moves. From 22° to 10° the eyes' light floods
the whole screen (`LidCurves.flood`, drawn by `FloodRenderer` over everything,
the eyes drawn again on top); the 16°→3° dark never touches it, so the screen
ends orange until shut, and it needs no capture, so it runs with the fold off. Its Metal layer stays
non-opaque, or the window server stops drawing the apps underneath. The
capture filter leaves NoSleep's own windows out, which is why the overlay is
not hidden with `sharingType = .none`: that would also blank the probe's
own-window captures.

**The fold never asks.** Any ScreenCaptureKit call without Screen Recording
raises the system prompt, and the fold runs unattended with the lid going
down, so everything checks `CGPreflightScreenCaptureAccess()` first; only the
Settings toggle's click calls `CGRequestScreenCaptureAccess()`. The grant is
tied to the code signature, and ad hoc signatures change with every build, so
each update (and each `make run`) drops it and the fold quietly falls back to
the cat alone until the user grants it again.

**The fold is Mac Duo's** (MIT): the ported files keep its notice in a header,
and THIRD-PARTY-NOTICES.md, which ships in the bundle, carries the licence.
The curves match the home page's (`site/lib/laptop-scene.ts`); change both.

**The panel is the system's own UI.** Liquid Glass tiles (`glassEffect`), the
native `Slider` and `Toggle`, the `.glass` button style. Don't draw custom
controls or use gradients. Everything glass sits behind an `if #available(macOS 26, *)`
with a plain fallback, because the app still runs on macOS 14.

## House rules

Build the current requirement, and only it. Comments say why, not what. Tests
state the rule they protect, in a sentence that reads well in a failure log.
