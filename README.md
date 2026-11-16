# LiDirt (iOS Scan MVP)

Native iOS app for **field grade and volume estimating** with Apple LiDAR. Capture a site on Pro devices, multi-pass average into a DEM (~5 cm grid), review quality/coverage, and upload heightmap + metadata.

Not a certified survey. Contour intervals down to 1/8 inch are **display** on the smoothed surface.

## Requirements

| Need | Detail |
|---|---|
| Xcode | 15+ (Swift 5.9+, iOS 17 SDK) |
| Capture hardware | iPhone/iPad **Pro** with LiDAR (`supportsSceneReconstruction(.mesh)`) |
| OS | iOS 17+ |
| Non-LiDAR / Simulator | Capture is **blocked** — Unsupported Device UX; no fake DEM |

## Open & run (LiDAR Pro device)

1. Clone this repo (`git clone https://github.com/Woodsroamer802/LiDirt.git`) and open **`LiDirt.xcodeproj`** in Xcode (File → Open — not a random folder). If Xcode says the project is damaged/unreadable, pull latest `main`; a bad Features/GIS group entry was fixed there.
2. Select the **LiDirt** scheme and your physical Pro device (not Simulator for capture).
3. Set your Development Team under Signing & Capabilities.
4. Build & Run.
5. You should briefly see the **LiDirt logo** on yellow + a spinner, then the email stub login with the same mark. Enter any email → **Continue**.
6. **New project** → **Start scan**.
7. Allow location when prompted (optional; used for approximate north).
8. Tap **Begin pass** (3–2–1 countdown) → walk → **End pass** → **Start next pass** → **Begin pass** again for multi-pass averaging → **Finish scan** → review → **Upload**.
9. Delete finished scans from the project list (swipe) or review screen (confirm).
10. Delete whole projects from the project list (swipe) or project detail (**Delete project**).

### Grey screen / “Taking longer than expected”

That Xcode banner usually means the **debugger is still attaching**, not that LiDirt crashed. The first paint is gunmetal (brand) — if it never shows yellow **LiDirt** text, launch/debug is stuck.

Try in order:

1. Use a **USB cable** (wireless debugging often hangs here). Unlock the phone and tap **Trust**.
2. Stop the run → **Product → Clean Build Folder** → Run again.
3. **Product → Scheme → Edit Scheme… → Run → Info** → uncheck **Debug executable** → Run. If the login screen appears, the app is fine and only LLDB attach was stuck; re-enable Debug later over USB.
4. Reboot the phone, quit Xcode, replug USB, Run.
5. Confirm **Signing & Capabilities** has your Team (not empty) and the phone is iOS 17+.
6. Watch the Xcode console while launching — a red crash/exception means a different bug; copy that text.

### Field tips

- Countdown uses large black blocky digits on yellow — wait for it before walking.
- Do not walk until countdown finishes / Begin pass — sampling stays off until then.
- Allow Location when prompted so GPS + compass can orient the heightmap to north (approximate).
- **Green area** = square meters of cells that already hit ≥8 LiDAR samples. **Green of walked** = that share of cells you’ve actually walked (amber until ≥8). **Residual** = RMS sample noise in those cells (cm) — lower is steadier averaging.
- Green on the coverage tint means the **sample goal is met** (≥8 samples/cell), not “touched once.” Amber = incomplete. Goal % stays 0 until you Begin pass, walk, and revisit cells enough times.
- GPS / north box is **hidden by default**; tap the location button on scan, or enable **Settings → Scan HUD → Show GPS box on scan**.
- Move at a steady walking pace; pause if tracking says “Move slower / better light.”
- Revisit amber areas; end/start passes yourself for multi-pass averaging.
- North alignment uses phone GPS/compass when authorized — approximate, not survey-grade. Deny location to keep a local AR frame.
- Score &lt; 50 blocks upload by default; you can confirm “Upload anyway.”
- Footer copy: *Field grade estimating. Not a certified survey.*

## Simulator / CI

- Simulator builds are supported for UI and unit tests.
- **Start scan** is gated off — you get the LiDAR-required screen.
- Unit tests cover DEM averaging, quality score breakpoints, and `metadata.json` schema v1 (no device needed):

```bash
xcodebuild test \
  -scheme LiDirt \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiDirtTests
```

## What’s stubbed

| Piece | Behavior |
|---|---|
| Auth | Local email stub; mint in-memory bearer token |
| Upload API | Default base `https://api.lidirt.example/v1` accepts multipart locally (`stub: true`) |
| Real backend | Set API base URL in **Settings** and turn off example-host stub by pointing at a real host |
| Offline queue | Packages written under Application Support `UploadsQueue/`; retry from Upload status |
| Mesh OBJ / cells.jsonl | Not required for MVP upload (heightmap.f32 + metadata.json only) |
| GIS / GPS grade | `georef.method: none`; hooks only |

## Upload package

```text
scan-{scanId}/
  metadata.json     # schemaVersion 1, upAxis y, quality, 1/8 in contour preference
  heightmap.f32     # row-major float32 meters (ARKit Y); NaN = hole
  heightmap.png     # optional preview
```

## Project layout

Matches the scan MVP spec module layout under `LiDirt/`:

- `Features/Scan` — LiDAR gate, AR capture, DEM, quality, review
- `Features/Upload` — package writer, stub/real multipart, offline queue
- `Features/Projects` — local project list/detail
- `LiDirtTests` — DEMBuilder, QualityScorer, MetadataCodec

## Site map / GIS (trespass awareness)

From a project, open **Site map (GIS / boundaries)**:

- Live GPS position + compass
- Optional **USGS topo** tile overlay (public National Map)
- Optional **parcel / boundary** polygons from a URL you set in **Settings → GIS / property lines** (county ArcGIS FeatureServer layer root, or GeoJSON)

This is **OnX-like awareness**, not OnX: LiDirt does not ship a licensed nationwide private-parcel database. Boundaries are approximate and for helping avoid accidental trespass — not a survey or title opinion.

## Out of scope (still deferred)

Invoices, Foreman Mode, Stripe, full web ops dashboard, licensed nationwide parcel DB.

## Spec / product docs

Canonical product specs live in the LiDirt Project store (`docs/ios-scan-mvp-spec.md`, architecture plan, preferences). See also `docs/README.md` in this repo.
