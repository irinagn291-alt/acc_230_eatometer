# Eatometer

Measure the week, not the meal.

Eatometer is a personal food log for people who want an instrument, not a social feed. It records energy and macros from Open Food Facts, keeps every stroke on device, and has no account, ads, or remote configuration. It is not medical advice. Nutrition data is credited to [Open Food Facts](https://world.openfoodfacts.org).

Contact: https://eatometer.pro/contact-us

## Architecture

The app is a single Redux store (`MeterStore`) holding one `AppState` value.

- Views dispatch `MeterAction` enums. There are no ViewModels.
- `meterReducer(state:action:)` is the only function that writes state. It is pure.
- Middleware performs effects: Core Data writes, Open Food Facts calls, demo seed.
- Selectors (`ReadingSelector`, `AnalyticsSelector`, `CatalogSelector`) derive boards, ledgers and merged catalog hits.

This fits a calorie log because every screen reads the same ledger — today, the log, the 14-day horizon, and analytics — and a single reducer keeps slot rules, day keys and calibration honest. Core Data `NSFetchedResultsController` maps managed objects to sendable structs and hydrates the store; the UI never sees `NSManagedObject`.

File layout follows architecture role: `State/`, `Actions/`, `Reducers/`, `Middleware/`, `Selectors/`, `Views/`.

## Unique feature

**Analytics deep dive.** The Analytics segment (and a teaser on Reading) shows 7 / 30 / 90-day energy traces, weekday averages, a macro donut, adherence against the energy dial, and best/worst day callouts. Charts are drawn with `CALayer` and `UIBezierPath`. Weekly means use `swift-algorithms` `windows(ofCount: 7)`. Section identity uses `OrderedSet` from `swift-collections`.

Plan horizon: **14 days** ahead, shown inside the Log segment.

## How this app differs

- Instrument lexicon (`GaugeReading`, `DialCalibration`, `MeterStore`, `ReadingSelector`, `CalibrationAction`).
- One shell, four segments: Reading / Log / Analytics / Targets. Search and Scan push. Detail and Assign are one fused measurement screen.
- Slots: Reading I, Reading II, Reading III, Spot Check. Spot Check remaps to Reading I (Morning) when a future day is chosen.
- Search uses `GET /api/v2/search` with a fields list and `page_size=32`.
- Day keys are ISO8601 date-only strings.
- UIKit compositional collection views and diffable data sources only. No `UITableView`.
- VisionKit `DataScannerViewController` with a brass crosshair and live readout.

## Design

Scientific instrument. Light ivory drafting paper, brass accent.

| Token | Hex |
| --- | --- |
| background | `#F8F5EE` |
| surface | `#FFFFFF` |
| ink | `#333333` |
| accent | `#C9A227` |
| muted | `#9B968C` |

Baskerville for prose and headings. Baskerville with monospaced digit features for readings. Hard edges. Base spacing 8 pt.

## Art style and prompts

Style: technical blueprint diagram, precision instrument schematic, fine measurement linework, brass accents on ivory drafting paper, engineering annotation.

Exact prompt used for every asset (subject appended after the base clause):

- `etm_AppIcon` — the app's single emblem, centred, filling the canvas edge to edge; a single analogue gauge with needle and concentric rings; no text
- `etm_Splash` — a vertical hero composition of a tall precision calorimeter tower with a calm uncluttered centre band
- `etm_Onboarding1` — a person in linework examining a packaged food specimen through a precision optical instrument
- `etm_Onboarding2` — a handheld barcode measuring wand scanning a labeled package with dashed projection lines
- `etm_Onboarding3` — a circular target dial with concentric goal rings and a needle meeting a daily mark
- `etm_EmptyLog` — an empty cylindrical measuring vessel waiting to be filled
- `etm_EmptySearch` — a magnifying reticle over an empty specimen tray
- `etm_EmptyPlan` — an empty weekly schedule grid horizon with blank cells
- `etm_EmptyWish` — an empty wire basket on a laboratory shelf
- `etm_SlotReadingI` — a rising sun over a morning measuring cup
- `etm_SlotReadingIi` — a high noon sun over a midday plate caliper
- `etm_SlotReadingIii` — a crescent moon over an evening flask
- `etm_SlotSpotCheck` — a small lightning tick mark beside a pocket gauge
- `etm_MacroProtein` — a coiled helix chain emblem
- `etm_MacroCarbs` — a hexagonal ring chain emblem
- `etm_MacroFat` — a droplet with lipid bilayer rings
- `etm_ProductPlaceholder` — a generic unlabeled grocery carton
- `etm_CardBackdrop` — faint concentric dials and dimension lines
- `etm_Texture` — seamless graph-paper grid and tiny tick marks
- `etm_ControlFace` — the face of a single brass rotary dial knob
- `etm_ScanOverlay` — framing reticle targeting brackets, open in the middle
- `etm_TwistHero` — layered trend graphs, a donut ring and weekday bars
- `etm_SuccessMark` — a confirmation check mark inside a calibration stamp ring
- `etm_HeaderDecor` — a wide decorative ornamental band of repeating gauge ticks

## Build

Requires Xcode 16+, iOS 17 SDK, Swift 6.2.

```bash
cd App08_Eatometer
/Users/belzephyrus/Documents/gambling/21AUG/tools/xcodegen/bin/xcodegen generate
xcodebuild -scheme Eatometer -destination 'generic/platform=iOS' build
xcodebuild -scheme Eatometer -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Bundle identifier: `com.eatometer.meter`  
User-Agent: `Eatometer/1.0 (iOS; +https://eatometer.pro)`  
Demo seed (Simulator only, once): `etm.demo.v1`

Dependencies (SPM): [apple/swift-collections](https://github.com/apple/swift-collections), [apple/swift-algorithms](https://github.com/apple/swift-algorithms).
