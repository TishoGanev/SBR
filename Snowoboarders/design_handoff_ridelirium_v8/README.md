# Handoff: RideLirium v8 — Track screen, rider markers, sport setting

## Overview
The existing Snowboarder iOS app (UIKit, `Main.storyboard`, `SB*ViewController`, Mapbox `MGLMapView`, OpenSans-CondensedBold) is being renamed **RideLirium** (ridelirium.com). v8 tightens the current Track screen so the map is visible while recording, adds friend markers that show each rider's sport and state, and adds a sport setting (Ski / Board / Bike).

## About the design files
`RideLirium v8.dc.html` is an HTML **design reference**, not production code. Recreate it natively in the existing UIKit codebase using its established patterns. Open it in a browser with `support.js`, `ios-frame.jsx` and `assets/` alongside. On the left of the phone, the marker style picker should be set to **12 · Tag + colours + states** (the default) — that is the marker to build; the other styles are explorations.

## Fidelity
High-fidelity. Match colours, sizes and type exactly. All sizes in pt. Font: OpenSans-CondensedBold for everything (use ExtraBold weight where noted if bundled; otherwise Bold).

## Rename
- Replace user-facing "Snowboarder" with "RideLirium" (display name, About row → `ABOUT RIDELIRIUM`, any titles).
- Bundle id / target names are out of scope unless the team decides otherwise.

---

## Screen: Track (`SBTrackViewController`)

Full-bleed Mapbox dark map. Floating UI on top, nothing else covering it. **Remove the weather card.**

### 1. Top bar (top = safe area + 4, left/right 14, gap 10)
- **Profile button**: 48×48 circle, fill #353535, 2.5 white border, initials ("TG") 17 ExtraBold white. Shadow black 35% / y6 / blur 18. Tap → Settings.
- **Crew pill** (fills remaining width): height 48, radius 24, white, padding 8 left / 14 right, same shadow. Tap → crew/friends list (existing behaviour).
  - Left: friend chips, 32×32 circles, 2 white border, overlapping by −10. Fill = rider colour (grey #8C939D if offline). White sport glyph 18×18 inside.
  - Text (12 after chips): line 1 `RIDING WITH MAYA +2` 16 ExtraBold #353535, truncate tail. Line 2 `2 ON THE MAP · 1 OFFLINE` 11 Bold #8A8A8A, tracking 0.04em. 3 between lines.
  - Right: chevron 9×9, 2.5 stroke #BDBDBD.
  - Only **one** pill. The current build shows a second pill peeking behind — remove it.

### 2. Map controls (right edge, 12 from screen edge, stacked, gap 12, directly above the recording card)
All 48×48 circles, shadow black 35% / y4 / blur 14.
- **Show everyone**: white with #353535 people icon; when active, fill #353535 with white icon. Tap → fit camera to all online riders + user; turns Follow off.
- **Follow me** (only while recording): off = white with #ED213D outlined arrow; on = #ED213D with white filled arrow. Tap toggles; turning on recentres on the user.
- **Recenter** (idle only): white circle with dark location pin.
- These replace the current wide "SHOW EVERYONE" / "FOLLOW ME" pills (which wrap to two lines).

### 3. Recording card — compact (default while recording)
Left/right 12, bottom sits 12 above the tab bar. White, radius 24, padding 8 top / 14 sides / 14 bottom, shadow black 45% / y14 / blur 40. Vertical stack, gap 10.
- **Grabber**: 36×4, radius 2, #D6D6D6, centred, 20pt hit area each side. Tap/drag up → expanded card.
- **Main row** (gap 12):
  - Left column: status `● RECORDING · 00:22:01` 12 Bold #ED213D, tracking 0.04em (dot 7, pulses). Paused → `PAUSED`. Below (4 gap): speed 44 ExtraBold #353535, tabular figures, + unit `KM/H` 15 Bold #8A8A8A baseline-aligned.
  - Pause: 52×52, radius 16, #F2F2F2, pause bars #4D4D4D (play triangle when paused).
  - Stop: height 52, padding 18, radius 16, #ED213D, white 13×13 rounded square + `STOP` 18 Bold white. Shadow #ED213D 30% / y6 / blur 16.
- **Stats row**: top border 1 #EFEFEF, padding-top 10. 3 equal columns: label 11 Bold #8A8A8A (DISTANCE, MAX SPEED, ALTITUDE), value 20 ExtraBold #353535 tabular.
- Target height ≈ 150pt (current build ≈ 285pt).

### 3b. Recording card — expanded
The current large card (80pt speed, 28pt stats, 68pt Pause/Stop buttons) with the same grabber at top. Tap grabber → back to compact.

### 3c. Idle card
Unchanged from current: stats + `START TRACKING` button + `GPS LOCKED · 11 SATELLITES`.

### 4. Tab bar
Left/right 14, bottom 30, height 62, radius 31, fill white 86% + blur (UIVisualEffectView `.systemThinMaterialLight` is acceptable), shadow black 35% / y8 / blur 24, padding 6.
- Two tabs, equal width, gap 6: TRACK, STATS. Each 50 tall, radius 25.
- Active: fill #ED213D, icon + label white. Inactive: transparent, #353535.
- Label 16 Bold. **No separate settings button** — Settings is reached via the profile button.

---

## Rider marker — `SBRiderAnnotationView` (MGLAnnotationView)

Anchor: bottom tip of the pointer = rider coordinate (`centerOffset = (0, -height/2)`).

- **Pill**: height 38, radius 19, padding 4 (left/top/bottom) / 12 (right), HStack gap 8: coin + text. Shadow black 45% / y4 / blur 12.
- **Pointer**: triangle 12 wide × 7 tall, centred under the pill, same fill.
- **Coin**: 30×30 circle. Sport glyph 20×20 (template image, tint per state).
- **Text**: name 13 ExtraBold #353535; status 10 Bold, tracking 0.3, uppercase; gap 2.

| State | Rule (suggested) | Pill | Coin | Glyph | Status text / colour |
|---|---|---|---|---|---|
| Riding | update < 60 s, speed > 2 km/h | #FFFFFF | rider colour + 4pt halo (rider colour 30%) | white | live speed `34 KM/H` / rider colour |
| Stopped | update < 60 s, speed ≤ 2 km/h | #FFFFFF | white, 2.5 border rider colour | rider colour | `STOPPED` / #8A8A8A |
| Last seen | no update > 2 min | #C9CDD3 (pointer too) | #8C939D | #E4E7EB | `LAST SEEN 12M AGO` / #6A717B, name #4A515B |

Thresholds are suggestions — confirm with product. Hide after ~2 h.

Behaviour: animate coordinate changes 0.45 s ease-out. Layering: above the track line, below floating UI; the user's blue dot stays on top. At low zoom / when overlapping, fall back to a 16pt dot (#ED213D, 2.5 white border) or Mapbox clustering.

### Rider colours (stable per friend; also used for the crew-pill chips)
- oklch(0.62 0.17 250) ≈ #3D7FD9 blue
- oklch(0.62 0.17 150) ≈ #3A9E57 green
- oklch(0.62 0.17 300) ≈ #8C6AD6 purple
- oklch(0.62 0.17 75) ≈ #C17F1E amber
- oklch(0.62 0.17 20) ≈ #D2556B rose

Do not use #ED213D for riders — reserved for app UI and the user's own track.

---

## Settings — new "I RIDE" row
Inserted between UNITS and ABOUT RIDELIRIUM. Padding 18/20, bottom border 1 #E8E8E8, vertical gap 14.
- Row: `I RIDE` 18 Bold left; segmented control right, same style as UNITS (1.5 #353535 border, radius 10, segments padding 12/14, 15 Bold; selected #353535 bg / white text, unselected white / #353535): **SKI · BOARD · BIKE**. Default BOARD.
- Preview strip below: radius 14, fill #141B24, padding 12/14. Left `How friends see you` 13 SemiBold white 70%. Right: the user's own rider tag (riding state) with chosen sport glyph and label `SKIING` / `SNOWBOARDING` / `BIKING`.
- Persist locally (UserDefaults) **and** publish with the user's location payload so friends' devices render the right glyph.

## Data
Per friend: `id`, `name`, `coordinate`, `speedKmh`, `lastUpdate`, `colorIndex`, `sport` (`ski|board|bike`). State derived on device; refresh "last seen" every minute.

## Assets
- `Assets.xcassets/SportSki|SportBoard|SportBike.imageset` — vector SVG, template rendering, preserve vector data. Drop into the app's asset catalog. These are first-pass pictograms; swap for final art when available (same names).
- `Assets.xcassets/RiderGoggles.imageset` — goggles glyph from the app icon (used by non-sport fallbacks).
- `assets/` — same files for the HTML reference.

## Files
- `RideLirium v8.dc.html` — design reference (Track, Stats, Settings; marker style 12).
- `support.js`, `ios-frame.jsx`, `assets/` — needed to open the reference.
- `Assets.xcassets/` — Xcode assets.
