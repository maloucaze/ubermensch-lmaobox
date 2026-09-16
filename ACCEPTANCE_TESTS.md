# Ubermensch LMAOBox - Acceptance Test Plan

Version 2.2.1  
Last updated: 2026-09-15

## 1. Test principles

Every practical rule in `SPECIFICATION.md` MUST have an automated test. Pure
domain behavior runs outside TF2. LMAOBox access, callbacks, drawing, input, and
persistence use fakes. Live netprop propagation, actual player-resource behavior,
and screen rendering remain explicitly manual.

Tests MUST assert outcomes and fixed vectors rather than duplicate production
formulas. A passing desktop suite is necessary but not sufficient for live
compliance.

## 2. Exact calculations

Use full precision for all vectors. Expected times are seconds and differences
are from the local side's perspective.

| Local | Enemy | Local time | Enemy time | Time diff | Charge diff | Status |
|---|---|---:|---:|---:|---:|---|
| Stock 50 | Stock 40 | 20.0 | 24.0 | +4.0 | +10 | EQL |
| Stock 80 | Stock 50 | 8.0 | 20.0 | +12.0 | +30 | ADV |
| Stock 50 | Stock 80 | 20.0 | 8.0 | -12.0 | -30 | DIS |
| Kritz 50 | Kritz 40 | 16.0 | 19.2 | +3.2 | +10 | EQL |
| Kritz 100 | Kritz 100 | 0.0 | 0.0 | 0.0 | 0 | EQL |
| Stock 90 | Kritz 65 | 4.0 | 11.2 | +7.2 | +25 | EQL |
| Stock 100 | Kritz 65 | 0.0 | 11.2 | +11.2 | +35 | ADV |
| Stock 50 | Kritz 90 | 20.0 | 3.2 | -16.8 | -40 | DIS |

The executable table MUST also cover reciprocal and near-zero cross-family
cases, 0%, 100%, charge clamping, malformed numbers, unsupported families, and
the exact `-10`/`+10` inclusive boundaries plus values immediately outside.

### 2.1 Alive-player counts

The pure team-count suite MUST exhaustively resolve every pair from `0 vs. 0`
through `12 vs. 12` without classification. Tests MUST reject negative,
fractional, nonfinite, boolean, string, or missing counts. They MUST prove
local-team-first resolution for both RED-local and BLU-local views, exact
`<LOCAL_ALIVE> vs. <ENEMY_ALIVE>` formatting, fixed white text, absence of
`ADV`/`DIS`/`EQL` or any threshold result, and exact white `- vs. -` output
whenever complete roster authority or either count is unavailable. Tracker
tests MUST prove that all connected, valid, alive RED/BLU classes count, that
current lifecycle overrides lagging resource lifecycle before counting, and
that unavailable roster data does not retain a factual count.

## 3. Point estimation

Every estimate MUST be recomputed from its original trustworthy anchor and
elapsed monotonic time. Fixed vectors include:

| Anchor | Phase/state | Elapsed | Estimated charge | Active |
|---|---|---:|---:|---|
| Stock 50 | running inactive | 4.0 | 60.0 | false |
| Kritz 50 | running inactive | 4.0 | 62.5 | false |
| Stock 50 | setup inactive | 2.0 | 65.0 | false |
| Stock 99 | running inactive | 2.0 | 100.0 | false |
| Stock 100 | deployed | 2.0 | 75.0 | true |
| Kritz 60 | deployed | 4.8 | 0.0 | false |
| Stock 100 | deployed | 10.0 | 5.0 | false |
| Kritz 100 | deployed | 10.0 | 6.25 | false |

Tests MUST also cover phase-segment integration, charge clamping, nonfinite or
negative elapsed time, an estimate remaining at 100%, and repeated updates
proving that estimates are never re-anchored from prior estimates. No interval,
width cutoff, flashing bound, or probabilistic value may affect the result.

## 4. Tracking and source precedence

The pure tracking suite MUST cover these transitions:

1. A current charge, family, or deployment field is emitted unchanged with
   source `current`, independently of the other two fields.
2. Current charge remains usable when deployment is unreadable; current family
   remains usable when charge is unreadable; no partial failure rejects another
   valid field.
3. Current charge without family renders the charge with family `UNKNOWN`, while
   known family without charge renders `?%` with that family; both compare as
   unavailable rather than discarding the known field.
4. A validated player-resource value 73 creates the approximate point anchor 73
   with source `resource`, including when `mp_tournament` is disabled.
5. Valid resource values at both 0 and 100 are accepted; malformed,
   out-of-range, unavailable, or unassociated values are ignored.
6. A correctly associated deployment event anchors only its user id at 100% and
   starts the standard drain model.
7. With two Medics on one team, an event for the unselected Medic cannot alter
   the selected Medic's record; it may change selection only after its own record
   is updated.
8. An entity-index reuse cannot receive an event belonging to the prior user id.
9. A same-cycle current observation overrides event, resource, retained, and
   estimated values field by field.
10. Spawn and post-inventory events anchor 0% while retaining a supported family
   as last-known.
11. Death removes eligibility, clears charge/deployment, and retains a known
    supported family as a timestamped dead-Medic fallback.
12. Respawn removes the dead fallback; team/class changes, disconnect,
    identity replacement, and map reset invalidate incompatible dead records.
13. A map, local-team, or local-player change cannot leak incompatible records;
    self-Medic/team-mode transitions preserve still-valid records for others.
14. Reacquisition replaces estimates immediately, including a large correction.
15. Loss of readability after an anchor continues estimating indefinitely and
    never becomes `UNKNOWN` because of age alone.
16. Records prefer server user id over reusable entity index.
17. No raw entity or GameEvent is retained.

Event queues MUST retain order, cap at 64 entries, and discard the oldest entry
on overflow.

## 5. Adapter and player-resource boundary

Faked boundary tests MUST verify:

- local current charge uses `LocalTFWeaponMedigunData`;
- nonlocal current charge uses `NonLocalTFWeaponMedigunData`;
- the unqualified `m_flChargeLevel` path is never used as a charge source;
- per-player secondary loadout-slot lookup discovers supported Medi Guns without
  querying direct `CWeaponMedigun` enumeration;
- definitively dead and non-Medic players incur no active/loadout weapon reads,
  while a non-dormant player with unreadable class or alive state remains
  conservatively probeable;
- active-weapon and loadout observations associate each weapon with the correct
  owner and reconcile an identical weapon to one Medic record and one Medi Gun
  classification read;
- transient disagreement between active-weapon state and `m_bHolstered` cannot
  discard independently valid family, charge, or deployment fields;
- family, charge, and `m_bChargeRelease` reads are validated independently;
- an invalid deployment value cannot suppress a valid charge/family value;
- dormant entity/weapon netprops never become exact;
- CTFPlayerResource keeps a far/dormant Medic in the roster;
- connected, valid, team, class, alive, and user-id arrays are validated;
- player-resource arrays map entity index `N` to Lua table index `N + 1`;
- local user id is associated with local identity;
- validated player-resource charge is exposed as approximate in ordinary casual
  play and is not gated on `mp_tournament`;
- a valid current entity lifecycle field independently overrides a lagging
  resource field from the same capture;
- malformed or unavailable player resources fall back to entity enumeration
  without falsely confirming an empty global roster;
- raw team numbers 2 and 3 map to RED and BLU respectively;
- a disguised Spy is ignored and bots follow the same Medic rules;
- unsupported and unknown item definitions fail closed;
- relevant GameEvents are normalized, `player_chargedeployed.userid` is
  preserved, and irrelevant/malformed events are ignored;
- snapshot acquisition prefers `FRAME_NET_UPDATE_END`; when stage 4 is absent,
  `FRAME_RENDER_START` provides the compatibility capture; a delivered stage-4
  callback suppresses the immediately following stage-5 fallback; duplicate
  callbacks at one validated client/network revision perform no full
  acquisition; a changed revision or queued event captures immediately; an
  unavailable revision fails open; and the next Draw consumes the resulting
  resolved state without reacquiring it;
- context, MvM, round, console, and game-UI gates are defensive; and
- a malformed entity cannot prevent use of another readable entity.

## 6. Selection

Automated selection tests MUST verify:

- current or estimated active supported candidates outrank normal candidates;
- active candidates rank by greatest current/estimated remaining charge;
- normal candidates rank by earliest current/estimated time-to-ready, not raw
  percentage;
- outside the active/normal numerical tie tolerance, the better numerical value
  wins regardless of source;
- inside the tolerance, freshness orders current, resource, then estimated data
  before prior user id and entity-index fallbacks;
- active 0.1-point and normal 0.05-second ties retain the prior selection and
  otherwise use lowest entity index;
- dead candidates never participate in living-Medic selection, and unsupported
  candidates are ignored;
- any current, resource, retained, or estimated supported candidate outranks an
  unidentified roster fallback in the relevant active/normal group;
- an unidentified Medic is selected only when no numerically trackable eligible
  candidate is available; and
- ally and enemy selection are independent;
- a living unknown Medic outranks every dead fallback; and
- with no living candidate, dead selection retains the prior user id, otherwise
  chooses the most recent authoritative death, then lowest entity index.

## 7. State resolution

Automated state tests MUST cover:

- alive local Medic versus selected enemy, ignoring other allies;
- every non-Medic class and dead local player using team mode;
- confirmed missing side as compact `NO MED`;
- a retained authoritatively dead supported Medic as compact `DEAD MED`;
- dead fallback clearing on respawn/class/team/disconnect/map transitions;
- two unavailable sides as `EQL | 0% | -`;
- supported zero versus missing still using known-side ADV/DIS precedence;
- genuinely unknown family/charge producing `-` on the third line, never zero;
- estimated points remaining comparable with `ADV`, `DIS`, or `EQL` and a
  border;
- approximate resource data remaining comparable and bordered;
- identity loss preserving last team lines but withdrawing the old factual
  comparison with `-` when no trustworthy anchor applies;
- complete roster omission clearing obsolete selection identity;
- failed roster reads never proving `NO MED`; and
- map/team/local-player resets and comparison-mode transitions that preserve
  still-valid nonlocal Medic tracking;
- complete authoritative rosters resolving local-first alive counts without
  classifying them or depending on Medic selection; and
- incomplete roster authority resolving the team-count line as unavailable
  without retaining prior factual counts.

## 8. Formatting

The exact baseline MUST be:

```text
RED |  75% |   8s | KRITZ
BLU |  50% |  20s | STOCK
ADV | +25% | +12s
8 vs. 3
```

The BLU-local mirror MUST put BLU first. Missing, estimated, and genuinely
unknown examples MUST be tested exactly:

```text
RED |  75% | 10s | STOCK
BLU | NO MED
ADV | +75% |   -
8 vs. 12
```

```text
RED |  ~88% |  ~5s | STOCK
BLU |   73% |   9s | KRITZ
EQL | ~+15% | ~+4s
8 vs. 12
```

```text
RED | ?% | - | UNKNOWN
BLU | ?% | - | UNKNOWN
-
- vs. -
```

Compact death MUST be tested exactly as `RED | DEAD MED` (or the corresponding
BLU line).

Formatting tests MUST cover half-away point rounding, `~` on estimated/resource
percentages, team readiness, and differences; retained-family readiness marked
approximate; positive signs; negative zero normalization; whole-second team
readiness; whole-number time differences; printable ASCII; exactly four text lines;
and exact `-` team readiness when either required side field is unavailable or
the side is incomplete. They MUST prove aligned numeric columns, compact
missing/dead lines, exactly one separator-padding space per side, and that no
interval or `UNCERTAIN` text
is emitted. A deployed side MUST use the same readiness text calculation as an
inactive side at the same family and charge. Cache tests MUST prove a team line
is rebuilt when its rounded readiness changes even if its rounded percentage
does not. Team-count formatting MUST use exactly
`<LOCAL_ALIVE> vs. <ENEMY_ALIVE>` without Uber-column padding or a status, and
its cached line MUST rebuild immediately when either count changes.
The font contract MUST use the fixed-width Lucida Console face at size 14 and weight
600 so character-column alignment is also visual alignment under the
four-text-call render contract.

## 9. Colors and border

Automated tests MUST assert every fixed RGBA value in the specification.
Deployment team color precedes ready yellow; current or estimated 100% precedes
ordinary white. The third line is green, red, or white for `ADV`, `DIS`, or
`EQL`; `-` is white. `NO MED` and `DEAD MED` are gray. No amber status role exists.
Separate team-count constants MUST contain the specified white text and gray
separator RGBA values. The fourth line MUST remain white for factual and
unavailable counts.

The dark-yellow border MUST be absent for current, confirmed-missing, and
confirmed-dead inputs alone, and present
if either side is resource-derived, estimated, retained, or unknown, or roster
authority is unavailable.
The panel remains one background rectangle plus one separator rectangle and
four warning-border strips.

Position and renderer tests MUST prove that fractional normalized placement and
fractional measured dimensions are rounded to integral, fully clamped draw
coordinates. Fake LMAOBox drawing APIs MUST reject fractional numeric arguments
so controller tests exercise the real boundary constraint.

## 10. Controller and lifecycle

Controller tests MUST drive consecutive frames to prove:

- current family, charge, and deployment changes captured at the preferred
  `FRAME_NET_UPDATE_END`, or the stage-5 compatibility fallback when stage 4 is
  absent, appear on the next Draw;
- a current charge continues updating even when family or deployment reads fail;
- one side continues updating while the other advances from its immutable
  trustworthy anchor;
- far/dormant data never remains silently exact;
- current reacquisition removes the warning border once every selected
  non-missing field is current;
- events are queued without performing domain work inside the callback;
- deaths, respawns, connects, disconnects, and team changes reflected by the
  next authoritative reconciliation update the fourth line for the next Draw;
- rendering remains one four-line widget with one separator per eligible frame;
- dragging is menu-only, preserves pointer offset, clamps to screen, and saves
  only on completion/unload; and
- unload is idempotent and disables subsequent work.

Application tests MUST verify complete startup capability reporting, callable
host proxies, optional persistence fallbacks, stable reload-safe
FrameStageNotify, Draw, FireGameEvent, and Unload callback ids, callback cleanup,
and the generated self-contained bundle under fake globals.

## 11. Performance and resource bounds

Automated tests and static review MUST establish that:

- repeated eligible Draw calls create no additional fonts and render exactly one
  background rectangle, one separator rectangle, and four text calls per frame;
- warning-border frames add exactly four border rectangles and no extra text;
- newly readable current fields appear on the next Draw after network capture;
- ordinary non-dragging Draw calls cause no position writes, and a completed drag
  causes only the specified save;
- a closed menu causes no mouse-position or mouse-button queries, while opening
  the menu preserves the documented drag behavior;
- unchanged formatting and layout reuse their bounded prepared/bounds storage,
  but rounded text, colors, warning state, resolution, position, and dragging
  still invalidate the appropriate result;
- the event queue retains the newest 64 normalized events in order, drops older
  overflow, and is emptied after reconciliation;
- repeated frames with an unchanged full roster do not grow retained tracking
  records; map, local-team, local-identity, authoritative roster, and unload
  transitions remove obsolete records as specified;
- dead-candidate state remains bounded by retained roster records;
- the update and selection implementation uses no candidate sort or nested
  player-roster scan and remains linear in the available player slots; and
- alive-player counting occurs inside an existing linear tracking pass and adds
  no entity acquisition, Draw-time roster work, event-only count drift, or
  unbounded retained count history.

The performance suite MUST also establish that a 32-player roster containing
only two possible alive Medics performs active/loadout inspection only for those
two players, never performs direct weapon enumeration, and that protected member
reads do not allocate a new closure per boundary call. Validation-recorder tests
MUST establish cadence-gated raw diagnostics, immediate decision/event/Draw
records, forced diagnostic follow-up after an unsampled selection transition,
bounded buffering, and one batched same-part write per flush. Decision records
MUST include the fourth line, its color, and resolved alive counts so a
recording can audit the feature without trusting formatted text alone.

Performance-sensitive changes MUST be reviewed for avoidable per-frame resource
creation, file or network access, logging, and unbounded tables. Automated checks
must use structural invariants and call counts rather than a machine-specific FPS
threshold. Actual frame-rate impact and long-session stability remain manual.

## 12. Persistence and weapon mapping

Existing executable suites MUST retain strict position parsing, versioning,
fallback paths, one-warning behavior, and in-memory operation on failure.

Weapon tests MUST validate every centralized Stock/Kritz definition, explicit
Quick-Fix/Vaccinator rejection, unknown fail-closed behavior, and—when the
installed TF2 schema is available—the schema-derived family sets.

## 13. Static and manual gate

Before release:

1. `lua tests/run.lua` passes.
2. Every authored and generated Lua file parses with the selected compatible
   compiler.
3. Luacheck has zero warnings/errors.
4. LDoc completes without warnings when installed.
5. `tools/build_runtime.ps1 -Check` passes.
6. Installed schema verification passes when schema data is available.
7. The generated and deployed runtime copies match.
8. `MANUAL_TESTS.md` is completed in actual TF2/LMAOBox.

Run `lua tools/benchmark_hot_path.lua` before and after performance-sensitive
changes and report both comparative results. The benchmark does not replace the
manual in-game FPS and sustained-session checks.

No project claim may call live behavior fully verified while any manual item
remains unperformed.
