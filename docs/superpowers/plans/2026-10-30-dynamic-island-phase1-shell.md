# Dynamic Island Phase 1: Notch-Anchored Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed 612x176 hotkey panel with an island that is permanently anchored to the notch, springs between idle / compact ("ears") / expanded, and shows Now Playing in both compact and expanded forms.

**Architecture:** Pure, unit-tested value logic (`NotchGeometry`, `IslandShapeMetrics`, `IslandSelection`, `NowPlayingActivityMapper`) feeds an `@MainActor IslandCoordinator` that owns mode/hover/expand state and merges `ActivitySource`s. A thin AppKit `IslandPanelController` hosts one transparent click-through panel; SwiftUI draws the animated shape. Phases 2 and 3 only add new `ActivitySource`s and views on top of this.

**Tech Stack:** Swift 5, SwiftUI + AppKit, Combine, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-30-dynamic-island-design.md` (this plan is Phase 1 of 3; Phase 2 = system events, Phase 3 = timer + calendar, each planned after the previous one lands because they depend on the interfaces and on what the camera/sandbox spike finds).

## Global Constraints

- macOS 14+, Swift 5, no third-party dependencies, app stays sandboxed (no entitlement changes in this phase).
- New `.swift` files under `MeloDock/MeloDock/` and `MeloDock/Tests/` are auto-included; do not edit `project.pbxproj`.
- Tests touching `@MainActor` types must be `@MainActor`; tests wrap in `#if canImport(XCTest)` like the existing ones; `SettingsStore` tests use a throwaway `UserDefaults` suite.
- UI strings in code are English.
- One island only, anchored at the MacBook notch; on a display without a notch the idle island is hidden and an active island is a pill below the menu bar.
- Compact = notch width plus 56pt ear on each side; expanded = 612x176; pill (no notch) = 220x34; hover delay 0.3s; paused music stays in the ears 5 minutes (300s).
- Priorities (higher wins): timer 100, calendar 80, now-playing playing 60, capture 40, now-playing paused 20.
- No polling when idle beyond what exists today; the only new timer is the 15s paused-expiry check.
- Run commands from the repo root with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Review Focus

1. Notch geometry where the right auxiliary area starts at or before the left one ends (or safe-area top is 0): treated as "no notch", never a zero/negative-size island. Pinned in Task 1.
2. Music flapping playing -> paused -> playing -> paused: the 5-minute clock restarts at each new pause and never counts time spent playing. Pinned in Task 3.
3. Pointer enters and leaves in under 0.3s: no expansion; hotkey/click while a hover is pending cancels the pending hover. Pinned in Task 4.
4. Island disabled in Settings: no ears ever, but the hotkey still expands it, and collapsing hides it again. Pinned in Task 4.
5. Persisted `overlayVisible == true` from the old app must not start the new app expanded. Pinned in Task 5.

---

### Task 1: NotchGeometry

**Files:**
- Create: `MeloDock/MeloDock/Features/Island/NotchGeometry.swift`
- Test: `MeloDock/Tests/DomainTests/NotchGeometryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct NotchGeometry: Equatable {
      let centerX: CGFloat   // global screen coordinates
      let width: CGFloat
      let height: CGFloat
      static func make(screenFrame: CGRect, safeAreaTop: CGFloat, backingScale: CGFloat,
                       auxLeft: CGRect?, auxRight: CGRect?, fallbackCenterX: CGFloat) -> NotchGeometry?
  }
  ```
- Consumes: nothing. Port the logic of `notchCenterX`, `normalizedAuxiliaryArea`, `validatedNotchCenterX` from `IslandPanelController.swift:185-230` (backing-space rects divided by `backingScale`; local rects offset by `screenFrame.origin`; reject if `|center - fallbackCenterX| > max(60, screenFrame.width * 0.18)`).

- [ ] **Step 1: Write failing tests** in `NotchGeometryTests` (all use frame `(0,0,1512,982)`, left `(0,950,656,32)`, right `(856,950,656,32)`, safeAreaTop 32, scale 1, fallback 756 unless stated):
  - `testGlobalCoordinates`: result `== NotchGeometry(centerX: 756, width: 200, height: 32)`.
  - `testLocalCoordinatesOnSecondScreen`: frame `(1512,0,1512,982)`, fallback 2268 -> centerX 2268, width 200.
  - `testBackingSpaceRects`: scale 2, left `(0,1900,1312,64)`, right `(1712,1900,1312,64)` -> centerX 756, width 200.
  - `testNilWithoutAuxiliaryAreas`: both nil -> nil.
  - `testNilWhenCenterFarFromFallback`: fallback 300 -> nil.
  - `testNilWhenAreasOverlap`: right `(600,950,912,32)` -> nil.
  - `testNilWhenSafeAreaTopIsZero`: safeAreaTop 0 -> nil.
- [ ] **Step 2: Run to verify failure**
  Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MeloDock/MeloDock.xcodeproj -scheme MeloDock -destination 'platform=macOS' test -only-testing:MeloDockTests/NotchGeometryTests`
  Expected: build FAIL, `NotchGeometry` not defined.
- [ ] **Step 3: Implement** `NotchGeometry.make` as a pure function (width = `right.minX - left.maxX`, height = `safeAreaTop`; return nil on any rejection above).
- [ ] **Step 4: Run the same command.** Expected: 7 tests PASS.
- [ ] **Step 5: Commit** `git add MeloDock/MeloDock/Features/Island/NotchGeometry.swift MeloDock/Tests/DomainTests/NotchGeometryTests.swift && git commit -m "Add pure NotchGeometry"` (end message with the Co-Authored-By line from the session attribution).

---

### Task 2: Island modes, shape metrics, activity selection

**Files:**
- Create: `MeloDock/MeloDock/Domain/Models/IslandActivity.swift`, `MeloDock/MeloDock/Features/Island/IslandShapeMetrics.swift`
- Test: `MeloDock/Tests/DomainTests/IslandSelectionTests.swift`, `MeloDock/Tests/DomainTests/IslandShapeMetricsTests.swift`

**Interfaces:**
- Consumes: `NotchGeometry` (Task 1).
- Produces:
  ```swift
  struct IslandActivity: Identifiable, Equatable {
      enum Kind: Hashable { case nowPlaying, power, audio, capture, timer, calendar }
      enum Priority { static let timer = 100, calendar = 80, nowPlayingPlaying = 60, capture = 40, nowPlayingPaused = 20 }
      let id: String; let kind: Kind; let priority: Int
  }
  struct IslandSelection: Equatable {
      var primary: IslandActivity?; var secondary: IslandActivity?
      static func select(from: [IslandActivity]) -> IslandSelection  // priority desc, ties by id asc
  }
  @MainActor protocol ActivitySource: AnyObject { var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { get } }
  enum IslandMode: Equatable { case idle, compact, expanded }
  enum IslandShapeMetrics {
      static let earWidth: CGFloat = 56
      static let expandedSize = CGSize(width: 612, height: 176)
      static let pillSize = CGSize(width: 220, height: 34)
      static func size(for mode: IslandMode, notch: NotchGeometry?) -> CGSize
      static func hitRect(panelFrame: CGRect, size: CGSize) -> CGRect  // size centered on panelFrame.midX, flush to panelFrame.maxY
  }
  ```

- [ ] **Step 1: Write failing tests.**
  - Selection: `testEmptyYieldsNoPrimaryOrSecondary`; `testOrdersByPriorityDescending` (timer 100 / playing 60 / capture 40 -> primary timer, secondary playing); `testTieBrokenByIdAscending`; `testSingleActivityHasNoSecondary`.
  - Metrics with notch `(centerX 756, width 200, height 32)`: idle -> `200x32`; compact -> `312x32`; expanded -> `612x176`. Without notch: idle -> `.zero`; compact -> `220x34`; expanded -> `612x176`. `testHitRectIsCenteredAndTopFlush`: panel `(100,200,640,200)`, size `300x40` -> `(270,360,300,40)`.
- [ ] **Step 2: Run** `-only-testing:MeloDockTests/IslandSelectionTests -only-testing:MeloDockTests/IslandShapeMetricsTests`. Expected: build FAIL.
- [ ] **Step 3: Implement** the types above in the two files (`ActivitySource` goes in `IslandActivity.swift`).
- [ ] **Step 4: Run again.** Expected: all PASS.
- [ ] **Step 5: Commit** "Add island activity model and shape metrics".

---

### Task 3: Now Playing activity source

**Files:**
- Create: `MeloDock/MeloDock/Features/Island/NowPlayingActivitySource.swift`
- Test: `MeloDock/Tests/DomainTests/NowPlayingActivityTests.swift`

**Interfaces:**
- Consumes: `PlaybackState`/`PlaybackStatus` (`Domain/Models/PlaybackState.swift`), `IslandActivity`, `ActivitySource`.
- Produces:
  ```swift
  enum NowPlayingActivityMapper {
      static let pausedTimeout: TimeInterval = 300
      static func activity(for state: PlaybackState, pausedSince: Date?, now: Date) -> IslandActivity?
      // playing -> id "nowPlaying", .nowPlaying, priority 60; paused and now-pausedSince < 300 -> priority 20; otherwise nil
  }
  @MainActor final class NowPlayingActivitySource: ActivitySource {
      init(playbackStates: AnyPublisher<PlaybackState, Never>, now: @escaping () -> Date = Date.init, expiryInterval: TimeInterval = 15)
      func recheck()   // re-evaluates against `now()`; also called by the internal timer
  }
  ```
  The source records `pausedSince` when status becomes `.paused` from any other status and clears it on any non-paused status.

- [ ] **Step 1: Write failing tests.** Mapper: `testPlayingIsPriority60`, `testPausedWithinTimeoutIsPriority20`, `testPausedAtTimeoutIsNil` (exactly 300s), `testStoppedAndUnavailableAreNil`. Source (feed a `PassthroughSubject<PlaybackState, Never>`, mutable fake clock, collect emissions): `testPausedExpiresAfterRecheck` (pause at t0, clock t0+301, `recheck()` -> last emission `[]`); `testResumeAndRepauseRestartsClock` (pause t0, play t0+200, pause t0+250, clock t0+400 -> `recheck()` still emits the paused activity, because only 150s have passed).
- [ ] **Step 2: Run** `-only-testing:MeloDockTests/NowPlayingActivityTests`. Expected: build FAIL.
- [ ] **Step 3: Implement** both types; emit `[activity]` or `[]` on every state change and on `recheck()`.
- [ ] **Step 4: Run again.** Expected: PASS.
- [ ] **Step 5: Commit** "Add NowPlayingActivitySource".

---

### Task 4: IslandCoordinator

**Files:**
- Create: `MeloDock/MeloDock/Features/Island/IslandCoordinator.swift`
- Test: `MeloDock/Tests/IntegrationTests/IslandCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ActivitySource`, `IslandSelection.select`, `IslandMode`, `NotchGeometry`.
- Produces:
  ```swift
  @MainActor final class IslandCoordinator: ObservableObject {
      @Published private(set) var selection: IslandSelection
      @Published private(set) var isExpanded: Bool
      @Published var isIslandEnabled: Bool
      @Published private(set) var notch: NotchGeometry?
      var mode: IslandMode   // expanded if isExpanded; compact if isIslandEnabled && selection.primary != nil; else idle
      var onExpandedChanged: ((Bool) -> Void)?
      init(sources: [ActivitySource], isIslandEnabled: Bool = true, hoverDelay: TimeInterval = 0.3)
      func updateNotch(_ notch: NotchGeometry?)
      func toggleExpanded()
      func pointerEntered()   // schedules expand after hoverDelay only if mode == .compact
      func pointerExited()    // cancels pending hover; collapses if expanded AND the pointer had entered
  }
  ```
  `selection` is computed from the union of every source's latest list. Any `toggleExpanded()` cancels a pending hover.

- [ ] **Step 1: Write failing tests** using `PassthroughSubject`-backed fake sources and `hoverDelay: 0.02` with `XCTestExpectation`/`Task.sleep`:
  - `testIdleWithoutActivities`, `testCompactWithActivity`, `testToggleExpandsAndCollapsesBackToCompact`.
  - `testSelectionMergesMultipleSources`.
  - `testHoverExpandsAfterDelay`; `testHoverLeftBeforeDelayDoesNotExpand`; `testHoverInIdleNeverExpands`; `testPointerExitCollapsesWhenEntered`; `testHotkeyExpandedIsNotCollapsedByUnrelatedExit` (toggle, then `pointerExited()` without a prior enter -> still expanded); `testToggleCancelsPendingHover` (enter, toggle -> expanded, wait past delay, toggle -> compact stays compact).
  - `testDisabledIslandNeverShowsCompact` (mode `.idle` with an activity); `testDisabledIslandCanStillBeExpandedByToggle` (toggle -> `.expanded`, toggle -> `.idle`).
  - `testOnExpandedChangedFiresOnToggle`.
- [ ] **Step 2: Run** `-only-testing:MeloDockTests/IslandCoordinatorTests`. Expected: build FAIL.
- [ ] **Step 3: Implement** with a cancellable `DispatchWorkItem` (or `Task`) for the hover delay.
- [ ] **Step 4: Run again.** Expected: PASS.
- [ ] **Step 5: Commit** "Add IslandCoordinator".

---

### Task 5: Settings semantics

**Files:**
- Modify: `MeloDock/MeloDock/Persistence/SettingsStore.swift` (the `overlayVisible` initializer line), `MeloDock/MeloDock/Features/Settings/SettingsView.swift` (relabel the `showOnStartup` toggle to "Show island")
- Test: `MeloDock/Tests/IntegrationTests/SettingsStoreTests.swift`

**Interfaces:** `SettingsStore.showOnStartup` keeps its key (`settings.showOnStartup`, default true) and now means "show island". `overlayVisible` now means "island expanded" and always starts `false`.

- [ ] **Step 1: Add failing test** `testOverlayVisibleAlwaysStartsFalse`: write `defaults.set(true, forKey: "settings.overlayVisible")`, create `SettingsStore`, assert `overlayVisible == false`; and `testShowOnStartupDefaultsToTrue`.
- [ ] **Step 2: Run** `-only-testing:MeloDockTests/SettingsStoreTests`. Expected: the first new test FAILS (true is read back).
- [ ] **Step 3: Implement**: stop reading the persisted value in `init`; keep the `didSet` write. Relabel the toggle.
- [ ] **Step 4: Run again.** Expected: PASS.
- [ ] **Step 5: Commit** "Make overlayVisible session-only and relabel show-on-startup".

---

### Task 6: Island views

**Files:**
- Create: `MeloDock/MeloDock/Features/Island/NotchShape.swift`, `IslandShellView.swift`, `CompactNowPlayingView.swift`, `ExpandedMusicView.swift`
- Modify: `MeloDock/MeloDock/Features/Island/IslandView.swift` (delete after its content moves)

**Interfaces:**
- Consumes: `IslandCoordinator`, `IslandViewModel` (unchanged), `IslandShapeMetrics.size`, `MusicSpectrumView`, `PlayerControlsView`.
- Produces: `IslandShellView(coordinator: IslandCoordinator, viewModel: IslandViewModel)`; `NotchShape(bottomRadius: CGFloat): Shape` with animatable radius (top edge flat, bottom corners rounded, `.continuous`).

- [ ] **Step 1: Move the current `IslandView` body** (top row, progress, bottom row, volume, output picker, theme) into `ExpandedMusicView(viewModel:)` with no background, border, glow, clip or fixed outer frame; the shell draws those. Keep artwork/spectrum/controls identical.
- [ ] **Step 2: Implement `CompactNowPlayingView`**: 22pt artwork on the leading ear, `MusicSpectrumView` on the trailing ear (fits within `earWidth`).
- [ ] **Step 3: Implement `IslandShellView`**: top-center-aligned black `NotchShape` sized by `IslandShapeMetrics.size(for: coordinator.mode, notch: coordinator.notch)`, `.animation(.spring(response: 0.4, dampingFraction: 0.78), value: coordinator.mode)`; content switches on mode (idle: none, compact: `CompactNowPlayingView`, expanded: `ExpandedMusicView`); `.onTapGesture { coordinator.toggleExpanded() }` only when mode is not `.expanded`. Keep `.colorScheme(.dark)`.
- [ ] **Step 3b: Delete `IslandView.swift`.** It is replaced in Task 7.
- [ ] **Step 4: Verify it compiles** (the app target will not link until Task 7 updates the callers, so also complete Task 7 Step 1 before building).

---

### Task 7: Panel controller and app wiring

**Files:**
- Modify: `MeloDock/MeloDock/Features/Island/IslandPanelController.swift` (rewrite), `MeloDock/MeloDock/App/AppDelegate.swift`, `MeloDock/MeloDock/App/DIContainer.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `IslandPanelController(coordinator: IslandCoordinator, viewModel: IslandViewModel)`; `DIContainer.islandCoordinator: IslandCoordinator` (lazy; sources = `[NowPlayingActivitySource(playbackStates: islandViewModel.$playbackState.eraseToAnyPublisher())]`, `isIslandEnabled` bound to `settingsStore.$showOnStartup`).

- [ ] **Step 1: Wire**: `DIContainer` builds the coordinator; `AppDelegate.configureIslandPanel` creates the controller with it; hotkey, status-menu "Toggle Overlay" and the `.meloDockToggleOverlay` notification call `coordinator.toggleExpanded()`; `settingsStore.overlayVisible` follows `coordinator.onExpandedChanged`; remove the `showOnStartup` -> `panelController?.show()` call; keep the throttled polling in `IslandViewModel` keyed off `overlayVisible`.
- [ ] **Step 2: Rewrite the controller**: one borderless non-activating panel, 640x200, transparent, `.statusBar` level, same `collectionBehavior` as today, hosting `IslandShellView`; remove the corner-radius/mask code. `reposition()` builds `NotchGeometry.make(...)` from the preferred screen (reuse `preferredScreen()`, `NSScreen.safeAreaInsets.top`, `backingScaleFactor`, `auxiliaryTopLeftArea/RightArea`), calls `coordinator.updateNotch`, and anchors the panel top-center at `screen.frame.maxY` (notch) or `screen.visibleFrame.maxY` (no notch). Panel is ordered out when `mode == .idle && notch == nil` or when `!isIslandEnabled && !isExpanded`; observe `$selection`, `$isExpanded`, `$isIslandEnabled`, `$notch` with Combine.
- [ ] **Step 3: Click-through**: install global + local `.mouseMoved` monitors; on each event compute `hit = IslandShapeMetrics.hitRect(panelFrame:size:)` for the current mode, set `panel.ignoresMouseEvents = !hit.contains(NSEvent.mouseLocation)`, and call `coordinator.pointerEntered()/pointerExited()` on inside/outside transitions. Remove monitors in `deinit`.
- [ ] **Step 4: Build and run the full suite**
  Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MeloDock/MeloDock.xcodeproj -scheme MeloDock -destination 'platform=macOS' test`
  Expected: BUILD SUCCEEDED, all tests PASS (existing 3 + new).
- [ ] **Step 5: Manual check on the notched MacBook** (build Debug and launch): idle island blends into the notch and menu-bar items beside it are clickable; start music -> ears appear with artwork + spectrum; hover 0.3s expands, leaving collapses; click the ears expands; hotkey toggles; pause 5+ minutes (or temporarily lower `pausedTimeout`) returns to idle; turn "Show island" off -> no ears, hotkey still expands/collapses; unplug into an external display with lid closed -> pill below menu bar when music plays, hidden when idle.
- [ ] **Step 6: Commit** "Rebuild island as notch-anchored shell".
