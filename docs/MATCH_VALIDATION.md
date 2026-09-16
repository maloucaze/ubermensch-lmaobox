# Match validation recorder

The validation runtime records the evidence needed to compare Ubermensch's live
inputs, retained state, selection, and HUD decisions with the specification. It
runs the same production modules and renders the same widget as
`ubermensch.lua`; the only additions are validation-only adapter evidence and a
fault-isolated recorder observer.

This is development instrumentation, not the distributable product runtime.
The ordinary runtime does not contain the recorder modules and performs no
match logging.

## Build, install, and start

Generate and copy the validation runtime to `%LOCALAPPDATA%\lua`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_validation_runtime.ps1 -Deploy
```

Unload the ordinary runtime if it is active, then load the validator from the
LMAOBox console:

```text
lua_unload ubermensch.lua
lua_load ubermensch_validation.lua
```

The validation runtime uses the same stable callback identifiers as the product,
so it replaces an already registered Ubermensch callback set rather than drawing
a second widget. The console prints the exact first log path and confirms that
F8 creates a numbered marker. If no path is writable, it reports that recording
is unavailable but leaves the HUD operational.

Normally logs are created inside the TF2 installation:

```text
<Team Fortress 2>\ubermensch-validation\
```

One load is one recording session and may span multiple rounds, maps, and
matches. Each filename is unique. A long session rotates at 64 MiB into
`part01`, `part02`, and so on; every part from that session is required for
analysis. Parts are opened in binary mode so the 64 MiB limit is measured in
the same bytes written to disk. Sequence numbers remain physically increasing
across parts, and each `segment_start` points to the final preceding record.
Records are buffered and flushed about every five seconds, on map
transition, on callback fault, and on unload. A crash can therefore lose at
most the final short buffered interval. Same-part records are combined into one
physical write per flush to reduce synchronous filesystem overhead. Only a clean unload writes
`session_end`; its absence must be reported as an integrity limitation rather
than inferred to be a product failure.

Stop cleanly after the last match:

```text
lua_unload ubermensch_validation.lua
```

Confirm that the console reports `stopped`, the number of parts, and zero
dropped records. A nonzero dropped count means the evidence is incomplete and
must be called out during review.

## Markers and session notes

Press F8 once at the beginning and once at the end of an intentional scenario.
The console prints each marker number. Keep a small external note such as:

```text
1-2: local RED Stock build and deploy
3-4: enemy Kritz moved out of range and returned
5: enemy Medic visible but HUD appeared frozen
```

Markers include the active decision sequence, Draw result, blocker, and current
four-line HUD. They do not capture text typed by the player.

## Recommended coverage

Natural public matches provide useful evidence, but deliberately covering these
transitions makes the later audit much stronger:

1. Play alive Medic on RED and BLU, using Stock and Kritz, building, holstering,
   reaching 100%, deploying, dying, respawning, and visiting resupply.
2. Play a non-Medic while allied and enemy Stock/Kritz Medics build and deploy.
3. Observe a Medic nearby, move far enough for dormancy or disappearance, wait,
   and return. Mark the departure and return.
4. When possible, observe two supported Medics on one team, including separate
   deployments and a selection change.
5. Exercise no-Medic, unsupported Medi Gun, newly joined/unknown, death, class
   change, team change, disconnect, round transition, and map transition cases.
6. Open the scoreboard, chat, LMAOBox menu, Source console, and TF2 game UI;
   drag the widget once while the menu is open.
7. Leave the recorder active through a sustained, reasonably full match so
   heartbeat counters, memory bounds, and long-session behavior can be reviewed.

Record the TF2 build, LMAOBox build, map/server type, local team/class, scenario
notes, visible symptoms, and any console error separately. Player or server
names are not needed.

## What is recorded

The file is newline-delimited JSON. Every line has a format version, monotonic
time, sequence number, type, and data object. Important record types are:

- `session_start`, `segment_start`, and `session_end`: version, fixed recorder
  limits, rotation continuity, and final counters;
- `event`: every production event plus privacy-safe player/round/map lifecycle
  events relevant to interpreting a match;
- `context` and `map_transition`: capture stage, map, round, phase, local
  identity facts, roster authority, and discovery count;
- `resource_tables` and `resource_row`: table availability, disconnected and
  malformed-slot counts, N-to-N+1 association for connected or malformed rows,
  validation results, and accepted approximate charge;
- `current_player` and `weapon`: player/weapon dormancy, possible-Medic filtering,
  loadout/active discovery, ownership, canonical weapon choice, qualified charge-table path,
  independent family/charge/deployment reads, and rejected malformed fields;
- `snapshot_player`: the primitive values actually admitted across the adapter
  boundary;
- `tracker`: lifecycle facts, field-local sources, deployment deadline, and the
  immutable trustworthy charge anchor;
- `candidate`: every living candidate and retained dead fallback presented to
  the respective linear selectors, distinguished by `dead` and `died_at`;
- `decision`: the actual selected sides, mode, Uber comparison, resolved
  local-first alive-player counts, four formatted lines, colors, whole-second
  per-side readiness text, and warning-border decision used by the HUD;
- `selection_checkpoint`: a complete available product-pipeline checkpoint
  written immediately whenever either selected identity or dead/missing/unknown
  selection state changes, including the previous selection; it explicitly
  reports whether the same capture also contains raw adapter diagnostics and
  preserves even a one-capture transition independently of the normal detail
  cadence;
- `draw` and `draw_blocked`: the first Draw consuming a changed decision or a
  changed visibility blocker. A rendered record distinguishes the changed
  decision's capture sequence from the newest capture state that Draw consumed;
- `heartbeat` and `checkpoint`: bounded counters every five seconds and a full
  recovery state every thirty seconds. Heartbeats and the final session record
  aggregate preferred, fallback, and unexpected capture-route counts;
- `marker`, `callback_fault`, and `recorder_drop`: manual correlation, runtime
  faults, and explicit evidence-loss reporting.

Verbose adapter diagnostics and boundary/tracker deltas are collected and
evaluated at up to 10 Hz rather than on every product capture. Current-charge
delta suppression uses 0.5 percentage-point buckets. The exact value at every
emitted change is retained. Observable HUD/source/selection changes are recorded
immediately, independently of this detail ceiling. A selection checkpoint states
whether same-capture raw adapter diagnostics were available; an unsampled
selection transition forces a raw diagnostic sample on the next capture. The preferred/fallback
capture route is retained on emitted records and checkpoints but route
alternation alone does not duplicate an otherwise unchanged context or decision;
aggregate counts preserve that health evidence at low volume. Team-comparison
mode is serialized explicitly as `self_mode: false`, rather than being omitted.
Unchanged contexts and decisions are compared as scalar product fields before
JSON projection, unchanged data is not written again, and Draw only appends to
memory; disk flushing stays in capture/lifecycle paths.

The validation runtime remains intentionally heavier than `ubermensch.lua`.
Only one runtime should be loaded at a time, and FPS comparisons must record
ordinary and validation results separately. Recorder version 1.2.0 introduced
cadence-gated raw diagnostics, batched writes, five-second flushing, and
thirty-second checkpoints. Version 1.3.0 adds explicit dead-candidate,
death-time, and selected-dead-state evidence while preserving immediate product
decisions, events, markers, and Draw correlation. Version 1.4.0 added the fourth
team-count line and resolved alive-count evidence to decision records. Version
1.4.1 simplifies that evidence to the literal local-first counts and their fixed
white presentation.

## Privacy and evidentiary limits

Server user IDs are replaced by session-local aliases such as `U1`. Entity and
weapon indexes, teams, classes, item definitions, sources, lifecycle facts,
percentages, decisions, and event associations remain available. Names, Steam
IDs, chat, server addresses, and unrelated events are never written.

The recording can prove whether Ubermensch followed its rules using the data
LMAOBox supplied. It cannot reveal the true charge of a fully unobservable
Medic. When trustworthy data later returns, however, the trace can measure the
estimate's error, prove whether the correction was immediate, and show exactly
which source and dormancy/read condition preceded it.

Recorder output supports review; it does not automatically mark any item in
`MANUAL_TESTS.md` as passed. Only an actual observed product-runtime case with
adequate supporting evidence may be recorded as completed.
