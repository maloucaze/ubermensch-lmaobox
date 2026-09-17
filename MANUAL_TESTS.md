# Manual TF2/LMAOBox validation checklist

Version 2.3.0
Last updated: 2026-09-16

These checks require an actual TF2 session with current LMAOBox. Automated
desktop checks do not satisfy them. Record only observations actually made.

## Validation record

- Tester:
- Date:
- TF2 build:
- LMAOBox build:
- Server/map:
- `mp_tournament` value:
- Runtime SHA-256:

## Installation and callbacks

- [ ] `lua_load ubermensch.lua` reports no missing required API.
- [ ] Exactly one widget appears after repeated script reloads.
- [ ] Relevant gameplay events do not print callback errors.
- [ ] On a host that omits `FRAME_NET_UPDATE_END`, exactly one compatibility
      message reports the `FRAME_RENDER_START` fallback and the widget proceeds
      to `HUD active` without duplicate per-frame acquisition.
- [ ] At high uncapped FPS, same-tick callback suppression does not delay a
      newly changing local, allied, or enemy charge beyond the next network-tick
      Draw, and queued deployment/lifecycle events remain immediate.
- [ ] `lua_unload ubermensch.lua` removes the widget and all callbacks.
- [ ] The deployed file matches the repository-generated runtime.

## Exact local and nearby samples

- [ ] Alive RED Medic appears on the first line as RED.
- [ ] Alive BLU Medic appears on the first line as BLU.
- [ ] Local Stock charge tracks the in-game meter continuously.
- [ ] Local Kritz charge tracks the in-game meter continuously.
- [ ] Local Quick-Fix charge, 100% readiness, and ordinary deployment track the
      in-game meter continuously.
- [ ] Local Vaccinator shows `VACC`, its current charge, no time-to-ready, and
      no comparison status.
- [ ] Nearby allied Stock and Kritz samples track while playing another class.
- [ ] Nearby enemy Stock and Kritz samples track.
- [ ] Nearby allied and enemy Quick-Fix samples track while playing another
      class.
- [ ] Nearby allied and enemy Vaccinator samples show current charge without a
      time-to-ready or comparison.
- [ ] A visible Medic's changing percentage updates continuously instead of
      remaining on a retained or estimated value.
- [ ] Repeat the visible test while the Medi Gun is active and holstered, and
      record which states expose a current nonlocal charge.
- [ ] A valid percentage continues updating when deployment cannot be read.
- [ ] A valid family remains current when percentage cannot be read.
- [ ] A readable percentage with no readable/retained family remains visible as
      `RED | N% | - | UNKNOWN` and produces `-` on the third line, rather than losing
      the percentage.
- [ ] A readable/retained family with no charge anchor remains visible as
      `RED | ?% | - | STOCK` or its Kritz equivalent and produces `-`
      on the third line.
- [ ] Inactive `m_bChargeRelease` never appears deployed.
- [ ] RED deployment turns the RED line bright red.
- [ ] BLU deployment turns the BLU line bright blue.
- [ ] Both deployment colors can appear simultaneously.
- [ ] Exact inactive 100% is yellow and 99% is white.
- [ ] Vaccinator is white below 25%, yellow at 25% or greater, and never uses a
      RED/BLU deployment color.

## Distance and player-resource reliability

Use a map/server where the tested Medic can move far enough to become dormant.

- [ ] A known enemy Medic remains represented after leaving the update set.
- [ ] A known allied Medic remains represented after leaving the update set
      while the local player is not an alive Medic.
- [ ] Distance alone never changes a known alive Medic to `NO MED` or
      `DEAD MED`.
- [ ] The dark-yellow border appears as soon as a formerly exact side is no
      longer exact.
- [ ] A short ordinary gap changes `N%` to a continuously advancing `~N%` point
      estimate based on the last trustworthy charge and family.
- [ ] A known-family estimate continues indefinitely, reaches 100%, and never
      becomes `UNKNOWN` merely because it is old.
- [ ] Returning to range immediately restores each readable current field and
      removes the border once every selected non-missing field is current.
- [ ] A large difference between an estimate and reacquired current charge is
      corrected on the first Draw after the next network update.
- [ ] A never-observed distant Medic has unknown percentage/family columns and
      the third line is
      exactly `-`, not a fabricated status or zero.
- [ ] Join, disconnect, death, respawn, class change, and team change update the
      global roster without requiring proximity.

## Player-resource charge path

- [ ] In an ordinary casual match with `mp_tournament 0`, an identified distant
      Stock Medic shows a continuously refreshed resource-derived `~N%` value.
- [ ] Repeat for Kritzkrieg.
- [ ] Repeat for Quick-Fix.
- [ ] A valid distant Vaccinator resource percentage remains visible and
      approximate, but is not advanced by an estimator after resource/current
      data disappears.
- [ ] Resource-derived approximate data retains the dark-yellow border.
- [ ] Nearby exact data overrides the approximate resource value immediately.
- [ ] Valid resource endpoints 0 and 100 are accepted, while an unavailable,
      malformed, out-of-range, or unassociated row never becomes a charge
      anchor.

## Events and estimation

- [ ] An out-of-range `player_chargedeployed` changes a previously identified
      Medic to a `~100%` deployment estimate with the correct team color.
- [ ] With two same-team Medics, deploying the unselected Medic updates only that
      Medic's record and never changes the other Medic's charge.
- [ ] If the deploying Medic becomes the selected active candidate, the switch is
      attributable to that Medic's own deployment event and identity.
- [ ] Estimated deployment drains linearly over eight seconds, then starts ideal
      rebuilding from zero without modeling flashing.
- [ ] Quick-Fix follows the same eight-second deployment drain and resumes ideal
      rebuilding at 2.75 percentage points per second.
- [ ] A Vaccinator `player_chargedeployed` event does not fabricate 100%, an
      eight-second drain, or deployment color.
- [ ] Spawn and post-inventory events start a `~0%` estimate while retaining the
      supported family as last-known and showing the border.
- [ ] Switching among Stock/Kritz/Quick-Fix/Vaccinator is corrected immediately when the new current weapon
      becomes readable; the previous family is never allowed to override it.
- [ ] Re-observation after any event corrects each readable field on the first
      Draw after network capture.

## Selection

- [ ] In self-Medic mode, other allied Medics never replace the local player.
- [ ] In self-Medic mode, local Quick-Fix or Vaccinator remains selected even
      when an allied Stock Medic is ready.
- [ ] In team mode, each side independently selects nearest time-to-ready.
- [ ] A current or estimated active comparison-supported Medic outranks non-active
      candidates.
- [ ] Within the active/normal group, candidates select greatest active charge or
      nearest normal time-to-ready using current or estimated point values.
- [ ] When readiness differs by more than the selection tolerance, the better
      point value wins regardless of source freshness.
- [ ] Within the selection tolerance, freshness orders candidates as current,
      then player resource, then estimated after the Stock, Kritzkrieg,
      Quick-Fix family tie-break; a remaining tie retains the previous server
      user id and finally uses the lowest entity index.
- [ ] At equal readiness, Stock wins over Kritzkrieg, which wins over Quick-Fix;
      outside the tolerance the numerically earlier readiness still wins.
- [ ] Vaccinator is selected only when no living comparison-supported Medic is
      available, and it is preferred over unknown/custom equipment.
- [ ] A nearby identified comparison-supported Medic remains selected even when another
      roster Medic has unknown weapon/charge data.
- [ ] An unknown Medic is displayed only when no numerically trackable eligible
      candidate is available on that side.
- [ ] Death or a move to a lower support tier immediately triggers reselection.
- [ ] If no living candidate remains, any Medic who dies becomes
      `TEAM | DEAD MED`; any living candidate, including an unknown one, takes
      precedence.
- [ ] With multiple dead Medics and no living candidate, the previous
      selection remains; without it, the most recent death is represented.
- [ ] Respawn removes `DEAD MED`; class change away from Medic, disconnect, map
      change, and identity replacement clear it; a Medic team change moves the
      fallback to the new team.

## Text, status, and colors

- [ ] The widget always has exactly four ASCII text lines in supported gameplay,
      with a one-pixel gray separator between the third and fourth lines.
- [ ] Current (`N%`), estimated/resource (`~N%`), and unknown (`?%`) columns,
      plus compact `TEAM | NO MED` and `TEAM | DEAD MED`, match the specification.
- [ ] Each supported numeric side shows its whole-second time-to-ready; exact
      readiness uses `Ns`, approximate or retained-input readiness uses `~Ns`,
      and missing or incomplete sides use `-`.
- [ ] `QF` participates in the normal percentage/readiness/status layout;
      `VACC` shows percentage with `-` readiness and forces the third line to
      exactly `-`.
- [ ] Exact charge/time signs and rounding match known test values, including a
      team-line readiness boundary where the percentage display does not change.
- [ ] Estimated inputs retain `ADV`, `DIS`, or `EQL` based on their point
      values and prefix displayed numerical differences with `~`.
- [ ] No interval or `UNCERTAIN` status is ever shown.
- [ ] Percentage and time tokens are right-aligned across normal team and status
      lines, and all displayed numbers use no decimal places.
- [ ] Cell separators use exactly one padding space on each side; extra leading
      spaces appear only where numeric right alignment requires them.
- [ ] Lucida Console 14 at weight 600 is readable in motion and keeps the padded
      numeric columns visually aligned.
- [ ] Missing/dead-side lines are gray, compact, and cause no warning border by
      themselves; genuinely unknown comparisons show exactly
      `-` and fabricate no zeroes.

## Alive-player counts

- [ ] The fourth line is always ordered as local alive players versus enemy
      alive players while playing on RED and while playing on BLU.
- [ ] Every connected, valid, alive RED/BLU player counts regardless of class;
      dead players, spectators, unassigned players, disconnected slots, and
      invalid rows do not.
- [ ] Death, respawn, connect, reconnect, disconnect, and team-change scenarios
      update the counts on the next observed authoritative reconciliation.
- [ ] The fourth line contains only `<LOCAL_ALIVE> vs. <ENEMY_ALIVE>` and never
      adds `ADV`, `DIS`, `EQL`, a threshold, or another classification.
- [ ] Representative small, medium, and full-team combinations—including
      `0 vs. 0`, `1 vs. 2`, `5 vs. 11`, and `12 vs. 12`—display their literal
      counts unchanged.
- [ ] Temporarily unavailable or incomplete roster authority displays exactly
      `- vs. -` in white instead of retaining last-known counts.
- [ ] The team-count line remains white for every factual and unavailable value
      and never changes the color of the three Uber lines.
- [ ] Count changes do not add an extra polling cadence, delay Uber updates, or
      cause Draw-time entity acquisition.

## Visibility, position, and persistence

- [ ] Widget remains visible while dead, using team mode where possible.
- [ ] Widget remains visible with no Medic on either team.
- [ ] Scoreboard, chat, and LMAOBox menu do not hide it.
- [ ] Source console, TF2 game UI, MvM, and unsupported round states hide it.
- [ ] Dragging works only from inside the widget with the LMAOBox menu open.
- [ ] Pointer offset is preserved and all text-width variants remain on-screen.
- [ ] Position persists across reload and game restart.
- [ ] Read-only persistence failure prints one warning but leaves HUD operational.

## Performance and long-session stability

Record the hardware, display resolution, server player count, graphics settings,
and FPS sampling method so the comparison can be repeated. Use the same map,
location, view direction, and server conditions for loaded and unloaded samples;
do not treat normal match-to-match variation as a script result.

- [ ] Compare a stable FPS sample with the script unloaded and loaded. No
      repeatable material FPS loss or frame-time stutter is attributable to the
      widget.
- [ ] Record separate samples for the ordinary runtime and the heavier validation
      runtime; do not attribute recorder overhead to the distributable script.
- [ ] Repeat at the fullest practical roster size (preferably 32 players) while
      current, resource-derived, estimated, retained, and unknown states occur.
- [ ] Exercise self-Medic and non-Medic team modes, deployment changes, the
      data warning border, scoreboard/menu visibility, and dragging without a
      visible update delay or input hitch.
- [ ] Leave the script loaded for at least 20 minutes while players join/leave and
      while changing class, team, round, and map. The HUD remains responsive and
      no progressively worsening stutter is observed.
- [ ] Inspect the LMAOBox console during the sustained run. No repeated runtime,
      drawing, persistence, or callback warning is emitted during ordinary
      frames.
- [ ] Repeat the comparison once with FPS substantially above the server/client
      tick rate. Increased render FPS does not cause proportionally repeated
      roster acquisition or progressively worsening garbage-collection hitches.
- [ ] Confirm position storage is not rewritten continuously; a write occurs only
      after completing a drag or when unloading a dirty position.
- [ ] Record unavailable scenarios and any observed FPS/frame-time difference;
      do not mark this section passed from automated tests alone.

## Result

- [ ] All applicable items passed.
- [ ] Failures, unavailable scenarios, and supporting console output are recorded
      below rather than being reported as passed.

Notes:
