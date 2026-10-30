# Expanded island redesign: implementation spec

Mockup: `island-expanded-redesign.html` (true scale, 1 css px = 1 pt; not verified in a browser or in SwiftUI).
Scope: `ExpandedMusicView`, `IslandShellView`, `IslandShapeMetrics`, `PlayerControlsView`, `MusicSpectrumView` (visual params only). Compact ears untouched. No behavior or feature changes.

## Decisions
1. `expandedSize` becomes **612 x 188** (was 176). Total shape = 188 + notch height (about 222 on a 34pt notch). Panel is 640x240, so it still fits (notch up to 52pt).
2. Three rows: identity (artwork, title/artist, source chip + spectrum), progress, transport (volume | play cluster | output). The play cluster is truly centered; volume and output occupy equal 180pt side slots.
3. Hierarchy: title 19 semibold white > artist 14 regular 70% > times 11 at 55%. Controls are bare glyphs, no capsule backgrounds. Only the two pickers are chips.
4. Artwork-derived tint: **skip**. It breaks the pure-black merge with the notch and needs image sampling. Revisit only as an artwork-colored spectrum.
5. Shape: flat top, bottom radius 30 (continuous), pure `#000`, no concave top flare.

## Tokens
| Token | Value | Use |
|---|---|---|
| island.bg | `#000000` | shape fill |
| text.primary | white 100% | title, glyphs |
| text.secondary | white 70% (about 10:1 on black, computed) | artist, volume icon |
| text.tertiary | white 55% (about 6.3:1, computed) | times |
| chip.fill / chip.hover | white 10% / 16% | pickers (replaces 9% fill + 13% stroke; drop the stroke) |
| track | white 22% | rail (decorative; the fill carries meaning) |
| fill | white 95% progress, 90% volume | |
| edge | 1pt inner bottom stroke, white 8% | separation on light wallpapers |
| shadow | black 40%, radius 14, y 6, drawn outside the clip on a background `NotchShape`; stays inside the 14pt panel margin | |
| radius | art 16, chip 14 (28h capsule), island bottom 30 | |
| spacing | outer H 24, top 16, bottom 14, row gap 10, art-to-text 16, chip gap 8 | |
| fonts | title `.system(19, .semibold)` tracking -0.2; artist `.system(14, .regular)`; chips `.system(12, .medium)`; times `.system(11, .medium, design: .rounded)` + `.monospacedDigit()` | |

## Layout (content 612x188, inner width 564)
- **Row 1, h72**: artwork 72x72 (radius 16, 0.5pt white 12% inner stroke; placeholder music.note 26pt). Text column fills the rest: title (1 line, tail truncation, `layoutPriority(1)`), artist 2pt below. Trailing column (VStack, space-between, h72, trailing): source chip on top, spectrum at the bottom with 5 bars, 3pt wide, 2pt gap, 16pt tall. Add `barCount`/`barWidth`/`barHeight` init params to `MusicSpectrumView` (defaults unchanged for compact). Remove the spectrum from the title line.
- **Source chip** (28h, padding H 10): `music.note` (Apple Music) or `dot.radiowaves.left.and.right` (Spotify) 12pt, name 12 medium, `chevron.up.chevron.down` 8pt at 70%. `Menu { Picker(...) } label: { chip }` with `.menuStyle(.button)`, `.buttonStyle(.plain)`, `.menuIndicator(.hidden)`, `.fixedSize()`.
- **Connect** (`authState != .authorized`): white-filled chip (black 12 semibold, 28h) left of the source chip, 8pt gap. Progress and transport render at 35% opacity (existing enabled logic unchanged).
- **Row 2 progress** (10pt below row 1, h30): 14h hit area across the full 564 with `DragGesture(minimumDistance: 0)`. Rail 4pt, no knob at rest. Hover or drag: rail grows to 6pt and a 12pt knob scales/fades in (`.spring(response: 0.25, dampingFraction: 0.8)`). Times 2pt below: elapsed leading, duration trailing, 11pt.
- **Row 3 transport** (2pt below row 2, h44): left slot 180 (`speaker.wave.2.fill` 14pt at 70% + 112pt custom slider, 4pt rail, 8pt gap, same hover/drag growth), center cluster (prev 44x44 hit, `backward.fill` 20pt; play/pause 44x44 hit, 30pt; next 44x44, `forward.fill` 20pt; 12pt gaps), right slot 180 trailing with the output chip. System `Slider` cannot be restyled on macOS, so use a custom capsule slider sharing the progress drag code.
- **Output chip** (28h, max width 180): `airplayaudio` 14pt + selected name 12 medium, tail truncated, chevron 8pt. Same `Menu` construction; empty list shows a disabled "No Outputs".

## States
- Chip: hover 16% fill; pressed 20% + scale 0.97; focus-visible 2pt white 60% ring; disabled 35%.
- Transport buttons: hover circle white 12%; pressed scale 0.92 + opacity 0.7; focus ring as chips; disabled 35%.
- Rails: hover/drag growth as above; while dragging, elapsed label shows the target time.
- Long text truncates tail; chips never wrap; no fixed-height clipping of text lines (title line box 24, artist 18) so Thai fits.
- A11y labels: "Playback position", "Volume" (with values), "Music source, <name>", "Audio output, <name>".

## Motion
- Expand: `.spring(response: 0.45, dampingFraction: 0.80)` on size and radius (12 to 30), slight overshoot.
- Collapse: `.spring(response: 0.34, dampingFraction: 0.92)`, no visible bounce.
- Content in: starts 0.05s after expand begins; three groups (identity, progress, transport) staggered 0.04s, each `.spring(response: 0.35, dampingFraction: 0.85)`: opacity 0 to 1, offset y 8 to 0, scale 0.96 to 1 anchored top. Optional blur 6 to 0 on all content (drop if costly).
- Content out: `.easeOut(duration: 0.12)` opacity to 0, no stagger, starting with the collapse. Content stays laid out at final size inside the animating clip, as today.
- Reduce Motion: shape `.easeInOut(duration: 0.2)`, content opacity only (0.15s), no offset/scale/stagger/blur; knob appears by opacity.

## Files that change
- `IslandShapeMetrics.swift`: `expandedSize = CGSize(width: 612, height: 188)`; update tests that assert 176.
- `IslandShellView.swift`: expandedRadius 30; separate expand/collapse springs; shadow on a background shape outside the clip; inner edge stroke; staggered reveal state; Reduce Motion path.
- `ExpandedMusicView.swift`: new `Layout`/`Theme`; add `SourceChip`, `OutputChip`, `ScrubRail`; drop `fieldCapsule`.
- `PlayerControlsView.swift`: glyph sizes, 44pt hit targets, hover/pressed styles (check other users first).
- `MusicSpectrumView.swift`: parametrize bar count/size only.
- `NotchShape.swift`: unchanged.

## Open questions
1. Is 188pt content height (+12) acceptable, or must it stay 176 (then use 36pt transport hit and trim gaps)?
2. Keep the volume slider always visible (kept, to preserve features) or collapse to an icon that expands on hover?
3. Keep elapsed/duration (kept) or elapsed/remaining like iPhone?
4. Is replacing the system volume `Slider` with a custom one acceptable?
5. Confirm skipping artwork tint.
