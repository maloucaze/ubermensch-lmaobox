# Architecture

Ubermensch separates maintainable authored modules from the one self-contained
file loaded by LMAOBox. This document describes the implemented version 2.2
architecture and the invariants its tests and build tooling enforce.

## Runtime data flow

```text
LMAOBox entity/player-resource APIs       FireGameEvent callback
                 |                                |
                 v                                v
 FrameStageNotify adapter -------------> bounded event queue
                 |                                |
                 +--------------+-----------------+
                                v
                             tracking
                    current/resource/estimate/?
                                |
                                v
           selection + team_counts -> state -> formatting
                                |
                                v
                    controller drawing/dragging
```

`adapter` is the volatile boundary. During the preferred capture at
`FRAME_NET_UPDATE_END`, or the authorized `FRAME_RENDER_START` compatibility
fallback, it validates gameplay context, the local player, global
`CTFPlayerResource` arrays, current
`CTFPlayer` entities, possible alive Medics' secondary loadout and active-weapon
handles, Medi Gun netprops, and monotonic time. The event
callback separately asks the adapter to normalize relevant `GameEvent` objects
immediately into primitive queued values. Per-player secondary loadout lookup is
the required primary weapon discovery path because the verified host returned
an empty direct enumeration; production no longer repeats that empty query.
Definitively dead and non-Medic players are filtered before weapon-handle reads,
while unreadable lifecycle fields remain fail-open for discovery. The
adapter returns plain values, associates observations through owner/resource
identity, and deduplicates the same owner/weapon. Player resources remain roster
authority and provide an approximate global charge source; entity/weapon
observations supply exact current fields and a defensive roster overlay.

`tracking` is pure domain state. Records are keyed by server user id when
possible, never by retained entity objects. Family, charge, deployment, and
roster facts have independent source/freshness metadata. Current valid fields
overlay all older sources individually; a failed deployment read cannot suppress
a changing current charge. A validated player-resource integer supplies an
approximate anchor without an `mp_tournament` gate, and missing current/resource
charge advances a deterministic point from the last trustworthy anchor. Every
estimate is recalculated from that original anchor, never from the prior frame's
estimate.

The tracker counts connected, valid, alive RED and BLU players while performing
its existing record-to-candidate pass. Current lifecycle overlays have already
been applied at that point, so the counts follow the same authority rules without
another roster scan. `team_counts` validates and maps the raw counts into
local-first order without classifying the difference. Counts are withheld rather
than retained whenever complete roster authority is unavailable.

An authoritative death clears charge/deployment state but retains a previously
identified supported family and the first observed death time. Tracking emits
these bounded records separately from living candidates. Respawn or an
incompatible lifecycle transition clears the dead fallback.

Queued `player_chargedeployed` events are matched by `userid` to one record. They
are never team-wide and never mutate another Medic merely because that Medic is
selected. Spawn and post-inventory events create a 0% anchor while retaining a
supported family as last-known. Contradictory current weapon evidence replaces
it immediately.

`selection` chooses one candidate independently for each relevant team. After
active priority, it ranks point values by greatest active charge or earliest
normal readiness. Freshness is a tie-breaker rather than a gate, so a useful
estimate remains selectable. Unidentified roster entries are fallbacks only when
no numerically trackable supported candidate exists.
Only when no living candidate exists does a second linear selector consider
dead supported records, retaining the prior identity before preferring the most
recent death and lowest-index tie-breaker.

`comparison` contains point readiness math for both current and estimated
values. `state` applies self-Medic/team-mode and
living/dead/missing/unknown precedence,
producing one normalized HUD view. `formatting` owns printable point text,
whole-second per-side readiness, approximate markers, and semantic color roles.
It derives each displayed readiness through the same comparison helper used by
selection and status math. Normal lines use dynamically aligned charge/time
columns and whole-number differences. Missing/dead sides use compact gray
forms, while an incomplete normal side shows `-` for readiness. Separators use
one space of cell padding on each side; any further leading spaces are solely
the dynamic right alignment of numeric tokens. A genuinely unavailable
comparison produces `-`; there is no interval or
`UNCERTAIN` state. The independent fourth line formats literal alive-player
counts or the white `- vs. -` unavailable form.

`controller` separates acquisition from presentation. FrameStageNotify uses the
optional validated client/network tick revision to discard duplicate callbacks
that cannot contain new simulation state, then captures, reconciles events,
resolves selection, and produces the latest prepared display state. A queued
event always forces reconciliation, and unavailable revision data fails open.
Draw consumes that state, measures, clamps, handles dragging, and draws.
The tracker owns primitive domain memory and its 64-entry event queue; the
controller owns normalized position and presentation state. `app` validates host capabilities and owns stable
FrameStageNotify, Draw, FireGameEvent, and Unload callback registration. Callback
identifiers deliberately exclude the version so a newer release replaces an
older callback set during reload. Registration and startup pre-clear invoke the
validated native callback proxies directly, while callback bodies remain
protected and fault-isolated. During host Unload, application cleanup runs and
returns before LMAOBox completes its owned script teardown. Non-host explicit
stops still unregister every stable id.

Other focused modules provide constants/item mappings, numerical primitives,
persistence, position behavior, safe boundary calls, and weapon classification.
Pure modules never access LMAOBox globals.

The controller also exposes a nil-by-default, fault-isolated observer boundary
for the development validation runtime. It synchronously reports normalized
events, completed capture decisions, first Draw consumption, callback faults,
and unload. With no observer—as in `ubermensch.lua`—the path is only a nil check
and no recorder module is bundled. The observer cannot replace product state or
turn a recording failure into a HUD failure.

When validation adapter diagnostics are explicitly enabled at composition, the
same adapter additionally returns primitive evidence about resource-table
validation, player/weapon dormancy, discovery paths, owner association,
canonical weapon choice, qualified charge-table reads, and independent field
failures. These values describe production boundary decisions; they are not fed
back into tracking and do not change precedence.

## Field-level freshness model

Precedence is resolved independently for each field:

1. current validated non-dormant weapon field;
2. fresh validated player-resource charge, for charge only;
3. correctly associated event fact;
4. last-known family or point estimate from a trustworthy charge anchor;
5. genuinely unknown only when no such fact exists;
6. confirmed dead only from retained supported family plus authoritative death;
7. confirmed missing only from a complete global roster when no dead fallback applies.

This hierarchy is fill-only below the first level: older sources fill fields that
are absent, but cannot replace a current value. A record can therefore have a
current charge, last-known family, and unknown deployment simultaneously. The
line remains useful, and the border communicates the non-current family or
deployment.

Unknown is also field-local. The presentation can preserve a `63%` charge with
family `UNKNOWN` when only family is unavailable, or `?%` with `STOCK` when
only charge is unavailable. In
either case comparison returns `-`, but the known field is not discarded.

Inactive estimates assume continuous ideal building at the fixed family rate.
Deployment estimates use standard eight-second linear drain, then ideal building
from zero. No flashing range or probability model is maintained. The point is
displayed with `~` and remains available indefinitely until a trustworthy
observation re-anchors it. When a required number or family has never been
learned, the third line is `-`.

## Hot path and resource bounds

Network capture at `FRAME_NET_UPDATE_END` is the preferred data hot path. A
small stage latch uses `FRAME_RENDER_START` only when the host omitted the
preceding stage-4 callback, and suppresses that fallback after a preferred
callback. A second latch rejects repeated callbacks within one validated
client/network revision; a changed revision or queued event captures, while an
unavailable revision fails open. Either path captures the current LMAOBox snapshot, reconciles
the bounded event queue and primitive tracking records, resolves both teams, and
prepares the four display lines once before Draw. Draw uses that latest prepared
result to measure and clamp the panel, handle the permitted drag gesture, and
draw once.
This timing ensures that a readable current field reaches the next Draw without
repeating entity acquisition in the drawing callback.

Roster capture and reconciliation use a small fixed number of player passes.
Only possible alive Medics incur active/loadout and Medi Gun reads, and identical
active/loadout handles are inspected once. Candidate selection is linear rather
than sort-based, so update time remains `O(P)` for `P` player slots. Protected
host member reads reuse a fixed pcall target rather than allocating one closure
per call. The event queue retains at most 64 normalized
events. Tracking stores no entity or GameEvent objects and is pruned or reset by
authoritative roster, map, team, identity, and unload transitions, preventing
growth across unchanged frames.

The controller creates its font once. Prepared text and bounds storage are
reused. The three Uber lines rebuild together only when a display-rounded token
changes because their numeric column widths are shared; the independent
team-count line rebuilds only when either count changes. Text measurement
compares the cached lines without constructing a combined key. The fixed-width
Lucida Console at size 14 and weight 600 turns character padding into
pixel-consistent, readable columns while preserving exactly four text calls. A closed
menu does not poll mouse coordinates or buttons. Each
rendered frame issues four text draws, one background rectangle, and one
separator rectangle, plus four rectangle calls when the warning border is
present. The position and measurement boundary converts normalized or
fractional values to clamped integer pixels because native LMAOBox draw calls do
not accept fractional coordinates. Steady-state frames do not access
persistence, the item schema, or the network; a dirty position can be written
only at drag completion or unload.

Formatting and measurement may be cached only if every invalidation
input—including content, font, screen size, position, drag state, colors, and
border state—is explicit. A slower roster cadence is unacceptable if it delays
current values or lifecycle changes.
Performance work is verified through deterministic call-count and resource-bound
tests plus controlled in-game FPS and long-session observation, not a portable
hardcoded FPS threshold.

## Self-contained runtime

`tools/build_runtime.ps1` discovers every `src/ubermensch/*.lua` file, wraps
it in a private module loader, and emits `ubermensch.lua` with a bundle-local
`require`. LMAOBox therefore loads one file and needs no runtime package path.

Use `-Deploy` after production changes; it regenerates the repository artifact,
deletes the prior `%LOCALAPPDATA%\lua\ubermensch.lua`, and copies the new file.
Use `-Check` in verification to detect a stale bundle without writing it.

`tools/build_validation_runtime.ps1` uses the same production modules and adds
only `tools/validation` to generate `ubermensch_validation.lua`. Its entrypoint
enables adapter evidence and supplies the recorder observer. Deployment replaces
only the previous validation runtime, not `ubermensch.lua`. The JSONL recorder
uses change-driven deltas, 5-second heartbeats, 30-second checkpoints, bounded
memory, and binary-mode 64 MiB rotation with physically monotonic cross-part
sequences. Capture-route alternation is counted rather than treated as an
observable decision change. Every selection identity transition produces an
immediate product-state checkpoint; when that capture was outside the 10 Hz raw
diagnostic cadence, the record says so and forces raw evidence on the next
capture. Unchanged context and decisions are compared as scalars before JSON
projection. Same-part buffered lines are written as one batch about every five
seconds. Draw records distinguish the changed decision from the newest capture
state consumed and performs no file I/O. The detailed workflow and evidence limitations are in
`docs/MATCH_VALIDATION.md`.

## Tests and development tools

`tests/run.lua` loads responsibility-focused suites.
`tests/support/harness.lua` owns assertions, `fixtures.lua` owns plain
domain samples, and `fakes.lua` owns
player entities, `CTFPlayerResource`, GameEvents, drawing/input, callbacks, and
persistence boundaries.

The tracking suite tests immutable anchors, point estimation, per-field source
precedence, sticky family, dead fallback lifecycle, and per-user deployment association. Adapter,
tracking, and application suites exercise primary loadout discovery without
direct enumeration, active/loadout deduplication, owner reconciliation, global
roster/charge arrays, event normalization, callbacks, and the bundled runtime.
State/selection/comparison/team-count/formatting/controller suites verify
current corrections, estimate marking, `-` fallback, literal alive-player
counts, and the visible four-line output.
Validation writer and recorder suites independently cover deterministic JSON,
collision-safe file creation, bounded buffering, rotation, privacy projection,
physical cross-part sequence continuity, delta suppression, capture-route
aggregation, selection checkpoints, exact Draw correlation, markers, and
observer-fault isolation.

`tools/check.ps1` runs tests, parses authored and generated Lua with `luac`, runs
Luacheck, builds LDoc with warnings fatal, checks both generated bundles, and optionally validates
the installed TF2 item schema. Luacheck and LDoc are development-only and are
not bundled.

`tools/benchmark_hot_path.lua` supplies a deterministic 32-player/two-Medic
fake-host benchmark for comparative capture/Draw time, protected boundary-call
counts, and allocation pressure. It is intentionally not an FPS benchmark and
cannot replace the controlled TF2 checks in `MANUAL_TESTS.md`.
