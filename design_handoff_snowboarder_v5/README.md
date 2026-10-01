# Handoff: Snowboarder v5

## Overview
v5 redesigns the existing Snowboarder iOS app, which is built with UIKit, `Main.storyboard`, `SB*ViewController` classes, Mapbox `MGLMapView` and OpenSans-CondensedBold.
- **Track:** the map fills the screen, with floating cards on top and a new **Follow Me** mode.
- **Navigation:** a floating red tab bar replaces the side menu.
- **Stats, Daily stats and Settings:** keep a red header.

## About the design files
`Snowboarder v5.dc.html` is an HTML **design reference**, a clickable prototype. It is not production code. Rebuild it natively in the existing app. Open it in a browser (keep `support.js` and `ios-frame.jsx` next to it) and try it: Start and Stop, drag the map, switch tabs, and tap a day. `Main.storyboard` is v1, included for mapping.

## Fidelity
**High fidelity.** Colours, type, spacing and copy are final. Map tiles, avatars and session data are placeholders.

## Architecture
| v1 | v5 |
|---|---|
| `SBMenuViewController` (side drawer) | Remove it. Add a root container VC that hosts 3 child nav controllers and a custom floating tab bar `UIView`. Don't use the system `UITabBar`, because the design floats and is pill-shaped. |
| `SBMainViewController` | Track tab |
| `SBStatsViewController` / `SBStatsCell` | Stats tab (nav root) |
| `SBDailyStatsViewController` | Pushed from Stats. Hide the system nav bar and use the header back link. |
| `SBSettingsViewController` | Opened from the avatar button in the tab bar |
| `SBAboutViewController` | Pushed from Settings → "About Snowboarder" |

- Hide the system navigation bar everywhere.
- Status bar: light content on the dark and red screens.
- Keep the tab bar above pushed screens so it's always visible.
- Every scroll view needs a bottom content inset of **110 pt** so nothing sits under the bar.

## Tokens
**Colours**

| Token | Value |
|---|---|
| Red | `#ED213D` |
| Charcoal | `#353535` |
| Secondary text | `#8A8A8A` |
| Light grey fill | `#F2F2F2` |
| Grey button text | `#4D4D4D` |
| Divider | `#E8E8E8` |
| Chevron | `#BDBDBD` |
| Map background | `#141B24` |
| Sun | `#FFB340` |
| User dot | `#1A7CFF` |

**Font:** OpenSans Condensed for everything. The HTML's 800 weight maps to CondensedExtraBold (fall back to CondensedBold if that isn't bundled) and 700 maps to CondensedBold. Use tabular figures on every live number.

**Radii:** 28 pt for the stats card, 26 pt for the tab bar and pills, 20 pt for chips and buttons.

**Shadows**

| Element | Offset y | Blur | Opacity (black) |
|---|---|---|---|
| Chips and map buttons | 6 | 18 | 35% |
| Stats card | 14 | 40 | 45% |
| Tab bar | 10 | 30 | 30% |
| Red button glow (`#ED213D`) | 8 | 20 | 30% |

## Screens

### Track (`SBMainViewController`)
The map fills the whole view, edge to edge and under the status bar. Everything else floats on top of it.

**Top chips:** top edge 62 pt from the top of the screen, 14 pt side insets, 10 pt gap between the two chips.
- **Weather chip:** flexible width, red background, 12/16 pt padding. It contains:
  - a 28 pt amber sun circle with a 2 pt white border
  - the temperature `14.7°C`, 22 pt ExtraBold, white
  - the line `SKY IS CLEAR · WIND 2 KM/H`, 13 pt Bold, white at 88% opacity, tracking +4%
- **Friends chip:** fits its content, white background. It holds three overlapping 26 pt avatars (−9 pt overlap, 2 pt white ring) and the count `3`, 18 pt ExtraBold, charcoal. This is a new feature that needs a backend; hide the chip if that isn't built.

**Bottom stack:** 12 pt side insets, bottom edge 104 pt above the bottom of the screen (clearing the tab bar), 12 pt between items. From top to bottom:

1. **Map button, right-aligned** (see Follow Me below for when each version shows):
   - **Idle:** a 52 pt white circle with a charcoal location pin. Tapping it re-centres the map.
   - **Tracking, following:** a red pill, 52 pt tall, with a white filled navigation arrow and `FOLLOWING` in 17 pt Bold white.
   - **Tracking, not following:** a white pill with a red outlined arrow and `FOLLOW ME` in red.
2. **Stats card:** white, 28 pt corner radius, 20/18/16 pt padding.
   - **While tracking**, the top of the card shows:
     - a red kicker, 14 pt Bold: a pulsing 9 pt dot (opacity 1 → 0.25, 1.4 s loop) followed by `RECORDING · 00:12:34`, or `PAUSED`
     - the current speed, 80 pt ExtraBold, with `KM/H` in 20 pt grey beside it
     - 14 pt of space below
   - **Always:** three columns, `DISTANCE` / `MAX SPEED` / `ALTITUDE`, 12 pt gap, 18 pt below.
     - Labels: 13 pt Bold grey.
     - Values: 28 pt ExtraBold charcoal, on one line.
   - **Buttons:** 68 pt tall, 10 pt gap between them.
     - **Idle:** a single red button: a 16 pt white circle and `START TRACKING`, 22 pt Bold white.
     - **Tracking:** `PAUSE`/`RESUME` (light grey fill, flex 1) and `STOP` (red, flex 1.4, a 16 pt white square with 3 pt corners).
   - **Idle only:** `GPS LOCKED · 11 SATELLITES` below the buttons, 12 pt Bold grey, tracking +8%.

**Map content**
- Live track: `#ED213D`, 4 pt wide, round caps.
- User dot: 22 pt `#1A7CFF`, 3 pt white border, with a 14 pt halo of `rgba(46,110,200,.22)`.

### Follow Me (new)
| Event | Result |
|---|---|
| Start tracking | `follow = true` → `mapView.userTrackingMode = .followWithCourse`. Use `.follow` if you'd rather keep north up. |
| User pans, pinches or taps the map | `follow = false`. Detect it with a pan/tap `UIGestureRecognizer` on the map (return `true` from `shouldRecognizeSimultaneously`) **and** in `mapView(_:didChange:animated:)` when the mode drops to `.none`. |
| Tap `FOLLOW ME` | `follow = true`, animated re-centre (~0.45 s, ease-out) |
| Tap `FOLLOWING` | `follow = false` |
| Stop tracking | Hide the pill and show the idle re-center button |

Only programmatic camera changes should keep follow on. Ignore region changes you triggered yourself, for example by checking `reason` on `regionWillChangeWith`.

### Stats
- **Red header:** 62 pt top padding (from the top of the screen, under the status bar), 20 pt sides, 22 pt bottom.
  - Kicker: `2025/26 SEASON · 41 DAYS`, 18 pt Bold, tracking +4%.
  - Hero: the total distance, 88 pt ExtraBold, tracking −2%.
  - Two-line caption, 20 pt Bold: `KM RIDDEN` / `78.9 KM/H TOP SPEED`.
- **Rows:** 78 pt tall with a divider. From left to right:
  - the day, 40 pt Bold, right-aligned in a 44 pt column
  - the month (red, 14 pt) above the year (grey, 13 pt)
  - the resort name (18 pt) above `38.10 km · 71.4 KM/H` (14 pt grey)
  - a chevron
  - The pressed row turns `#F2F2F2`. Tapping a row pushes Daily stats.

### Daily stats
- **Red header:**
  - A back link: white chevron plus `STATS`, with a hit target of at least 44 pt.
  - Kicker: `BOROVETS · 17 MAR · 09:12–15:40`.
  - Hero: that day's distance.
  - Caption: `KM` / `71.4 KM/H MAX`.
- **Map:** the day's route in red, 4 pt wide.
  - Start marker: 12 pt white circle with a red stroke.
  - End marker: 12 pt red circle with a white stroke.
- **Buttons:** `SHARE` (light grey) and `EXPORT` (red), each 64 pt tall. Leave 106 pt of bottom padding below them for the tab bar.

### Settings
- **Header:** red, with `SETTINGS` in 40 pt ExtraBold.
- **Rows:** 72 pt tall.
  - `UNITS`: a segmented control with a 1.5 pt charcoal border. The selected segment is charcoal with white text. Changing it converts every value in the app live.
  - `ABOUT SNOWBOARDER` with a chevron.

### Floating tab bar
- **Position:** 14 pt side insets, bottom edge 30 pt above the bottom of the screen, clear of the home indicator.
- **Bar:** 62 pt tall, red pill with 26 pt corners, 8 pt inner padding, 6 pt gap between items.
- **TRACK and STATS items:** equal width, 46 pt tall, 20 pt corners.
  - Icon (18 pt) and label (16 pt Bold) with 9 pt between them.
  - Active: `rgba(0,0,0,.2)` fill, white icon and label.
  - Inactive: white at 78% opacity.
- **Avatar:** a 46 pt charcoal circle with the user's initials in 15 pt ExtraBold white. It opens Settings, and shows a white ring (2 pt red gap, then 2 pt white) while Settings is open.
- **Daily stats:** keeps STATS active.
- **Icons:** suggested SF Symbols are `record.circle` and `chart.bar.fill`.

## State
- `trackingState`: `idle → riding ⇄ paused → idle`. Start resets the metrics and turns on follow. Stop saves the session, as v1 does.
- `follow: Bool`, driven by the table above.
- `units` is persisted. Conversions:

| Metric | Imperial |
|---|---|
| km | mi (×0.621) |
| km/h | mph (×0.621) |
| m | ft (×3.281) |
| °C | °F |

- Live metrics come from the existing CoreLocation pipeline, updated once per second. Weather comes from v1's existing lookup.

## Files
- `Snowboarder v5.dc.html`: the prototype
- `support.js`, `ios-frame.jsx`: needed to open the prototype
- `Main.storyboard`: v1, for mapping
