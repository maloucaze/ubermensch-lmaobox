# Ubermensch LMAOBox

[![CI](https://github.com/maloucaze/ubermensch-lmaobox/actions/workflows/ci.yml/badge.svg)](https://github.com/maloucaze/ubermensch-lmaobox/actions/workflows/ci.yml)
[![Lua](https://img.shields.io/badge/Lua-5.1%20%7C%205.4-2C2D72?logo=lua&logoColor=white)](https://www.lua.org/)
[![License: MIT](https://img.shields.io/github/license/maloucaze/ubermensch-lmaobox)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4?logo=windows&logoColor=white)

Ubermensch is a compact Team Fortress 2 HUD for the LMAOBox Lua runtime. It
compares the most relevant Medic on each team, keeps the local team first, and
shows the current alive-player counts without adding tactical noise.

## What it shows

```text
RED |  75% |   8s | KRITZ
BLU |  50% |  20s | STOCK
ADV | +25% | +12s
8 vs. 3
```

The first two lines show each selected Medic's charge, time-to-ready, and Medi
Gun family. The third compares the local side with the enemy as `ADV`, `DIS`, or
`EQL`; the fourth reports the literal alive-player counts in the same order.
In definite 6v6 or 4v4 competitive/tournament play, a second separator and
optional fifth line identify enemy Snipers and Spies:

```text
Off-class: SNIPER (2), SPY
```

The class token is white while at least one corresponding enemy is alive and
gray when all detected instances are dead. The line is omitted in Casual,
Highlander/9v9, uncertain formats, and when neither class is present.

- Stock, Kritzkrieg, and Quick-Fix participate in readiness and comparison.
- In team mode, Vaccinator is a lower-priority, display-only fallback with
  charge but no readiness or advantage calculation.
- When you are an alive Medic, your own Medi Gun is always used for your side.
  Otherwise, the HUD selects one living Medic independently for each team.
- Active charges take priority; other supported Medics are selected by earliest
  readiness, with stable tie-breaking.
- `NO MED` means the roster confirms that the team has no Medic. `DEAD MED`
  preserves the distinction when a tracked Medic is dead and no living Medic is
  available.
- The panel remains available while you are dead and can be dragged while the
  LMAOBox menu is open. Its position persists between sessions when storage is
  available.

All displayed values use whole numbers. A leading `~` marks an approximate or
estimated value, while `?%` and `-` preserve genuinely unavailable information
instead of inventing a value. The HUD does not draw a data-quality border.

The complete behavior is defined in the
[behavioral specification](docs/SPECIFICATION.md).

## Install and load

You need Windows, Team Fortress 2, LMAOBox with Lua enabled, and PowerShell.
A standalone Lua installation is not required merely to build or run the HUD.

From the repository root, generate the self-contained runtime and copy it to
`%LOCALAPPDATA%\lua\ubermensch.lua`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_runtime.ps1 -Deploy
```

Then load it from the LMAOBox console:

```text
lua_load ubermensch.lua
```

Before replacing a runtime that is already loaded, unload it first:

```text
lua_unload ubermensch.lua
```

Startup reports missing required LMAOBox APIs together instead of failing
silently. Position-storage failure produces a warning but does not disable the
HUD. For host assumptions and known compatibility details, see
[API and item-schema evidence](docs/API_AND_SCHEMA.md).

## Reliability and limits

Source visibility and entity dormancy can make exact remote weapon data
temporarily unavailable. Ubermensch does not force network updates or attempt
to bypass those limits. It combines several carefully separated sources:

- readable, non-dormant weapon fields are treated as current and take immediate
  priority;
- validated player-resource charge is useful at distance but is marked
  approximate;
- retained family information and deterministic estimates continue from the
  last trustworthy charge anchor when necessary;
- newly readable current information replaces weaker data on the next eligible
  update, even when the correction is large.

Estimates use standard ideal Stock, Kritzkrieg, and Quick-Fix rates. They do not
model Ubersaw gains, flashing, changing heal targets, custom server attributes,
or other unpredictable influences. The `~`, `?`, and `-` markers preserve that
distinction rather than presenting unavailable or estimated data as exact.

Automated checks cover calculations, tracking transitions, selection,
formatting, rendering contracts, callback lifecycle, generated bundles, and
faked LMAOBox boundaries. Actual netprop behavior, on-screen rendering, distance
transitions, and frame-rate impact remain separate in-game checks; their current
status is recorded in the [manual validation checklist](docs/MANUAL_TESTS.md).

## Development

Production code is organized as focused modules under `src/ubermensch`. The
build script combines them behind a private module loader so LMAOBox receives
one dependency-free `ubermensch.lua` file. Pure domain logic is tested outside
the game, while host APIs are exercised through fakes.

Generate both development runtimes and run the full repository checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_validation_runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1
```

When the installed TF2 item schema is available at the default path, include
its verification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -VerifyItemSchema
```

The complete check requires Lua, `luac`, Luacheck, and LDoc. CI exercises the
project with Lua 5.1 and 5.4, checks syntax and static analysis, builds API
documentation, verifies generated runtimes, and reruns generation to confirm
deterministic output. These tools are development-only and are not included in
the LMAOBox runtime.

Further reading:

- [Architecture](docs/ARCHITECTURE.md) — module responsibilities, data flow,
  freshness rules, and hot-path constraints.
- [API and item-schema evidence](docs/API_AND_SCHEMA.md) — documented host APIs,
  observed LMAOBox behavior, and TF2 weapon-definition provenance.
- [Acceptance test plan](docs/ACCEPTANCE_TESTS.md) — executable behavior and
  boundary contracts.
- [Manual validation checklist](docs/MANUAL_TESTS.md) — behavior that must be
  confirmed in TF2 rather than inferred from desktop tests.
- [Match validation recorder](docs/MATCH_VALIDATION.md) — privacy-conscious
  evidence collection for diagnosing live matches; it is not part of the
  ordinary product runtime.

## License

Ubermensch LMAOBox is available under the [MIT License](LICENSE).

Copyright © 2026 Nícolas Maloucaze.
