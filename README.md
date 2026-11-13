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

1. Clone this repo and open `LiDirt.xcodeproj` in Xcode on a Mac.
2. Select the **LiDirt** scheme and your physical Pro device (not Simulator for capture).
3. Set your Development Team under Signing & Capabilities.
4. Build & Run.
5. Sign in with any email (auth stub) → **New project** → **Start scan**.
6. Allow location when prompted (optional; used for approximate north).
7. Tap **Begin pass** (3–2–1 countdown) → walk → **End pass** → **Start next pass** → **Begin pass** again for multi-pass averaging → **Finish scan** → review → **Upload**.
8. Delete finished scans from the project list (swipe) or review screen (confirm).

### Field tips

- Do not walk until countdown finishes / Begin pass — sampling stays off until then.
- Green on the coverage tint means the **sample goal is met** (≥8 samples/cell), not “touched once.” Amber = incomplete.
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

## Out of scope (this MVP)

Invoices, Foreman Mode, full GIS overlays, Stripe, web ops dashboard.

## Spec / product docs

Canonical product specs live in the LiDirt Project store (`docs/ios-scan-mvp-spec.md`, architecture plan, preferences). See also `docs/README.md` in this repo.
