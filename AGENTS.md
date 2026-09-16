# Project instructions

## Authoritative requirements

- Read SPECIFICATION.md and ACCEPTANCE_TESTS.md completely before changing code.
- Read MANUAL_TESTS.md before reporting final verification or compliance.
- These files are normative. Every MUST and MUST NOT is an acceptance requirement.
- Do not modify either specification unless the user explicitly requests it.
- If the documents contain a genuine contradiction, report it instead of silently choosing an interpretation.
- Do not add features outside the documented scope.

## Repository workflow

- Treat `src/ubermensch` as the authored production source.
- `ubermensch.lua` is generated. Never edit it directly.
- After changing a production module, regenerate the runtime with
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_runtime.ps1 -Deploy`.
  This also removes and replaces `%LOCALAPPDATA%\lua\ubermensch.lua` so the
  installed runtime always matches the generated bundle. Use the build
  script without `-Deploy` only when local installation is intentionally not
  available, and report that the installed copy was not refreshed.
- Before finishing any code or test change, run
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1`.
- When an installed TF2 schema is available, also pass `-VerifyItemSchema` to
  `tools/check.ps1`. A nondefault installation may be supplied with
  `-SchemaPath`.
- Report missing development tools or unavailable in-game verification
  explicitly. Do not treat an unrun check as passing.

## Engineering standards

- Target the current LMAOBox Lua runtime and current Team Fortress 2 behavior.
- Verify LMAOBox APIs and weapon definitions against authoritative documentation or installed game data. Do not invent API behavior or item identifiers.
- Keep the runtime self-contained with no external runtime dependencies.
- Separate pure domain logic from LMAOBox entity access, persistence, input, and drawing.
- Keep callbacks thin and delegate to small, focused functions.
- Prefer simple functions and tables over class-like frameworks or speculative abstractions.
- Apply DRY where behavior or knowledge would otherwise be duplicated, but do not abstract code used only once unless doing so materially improves testing or clarity.
- Avoid global variables except unavoidable LMAOBox-provided globals.
- Centralize constants, fixed visual values, weapon-family mappings, display states, and formatting rules.
- Document modules, built-in values, non-obvious formulas, state precedence, and LMAOBox compatibility decisions.
- Comments should explain why, constraints, or API quirks; do not narrate obvious code.
- Track family, charge, deployment, and roster/lifecycle facts independently.
  A failed field read MUST NOT discard another current valid field from the same
  Medic.
- Treat current non-dormant data as an overriding overlay. Resource values,
  events, retained facts, and estimates may fill missing fields but may never
  overwrite a current valid observation.
- Derive every estimate directly from its last trustworthy anchor and elapsed
  monotonic time. Never re-anchor an estimate from a prior estimate or restore
  the removed interval/`UNCERTAIN` model.
- Key all retained Medic facts and `player_chargedeployed` events by server user
  id when available. Never apply a deployment event as team-wide state or to the
  currently selected Medic merely because that Medic is selected.

## Performance engineering

- Treat network-stage snapshot capture, tracking reconciliation, Medic
  selection, state resolution, formatting, layout, and drawing as
  latency-sensitive hot paths. Draw should consume the latest resolved state
  rather than repeat network acquisition unnecessarily.
- Preserve correctness and data honesty before optimizing. An optimization MUST
  NOT delay a newly readable current field, label a retained field as current
  after its source becomes unavailable, change selection or state precedence, or weaken defensive
  LMAOBox-boundary handling.
- Keep update work linear in the number of player slots. Use linear selection;
  do not sort candidates or introduce nested roster scans when a single or small
  fixed number of passes is sufficient.
- Create fonts and other invariant resources once during initialization. Ordinary
  steady-state Draw callbacks must not perform file I/O, schema inspection,
  network access, or routine console logging. Position persistence remains
  limited to drag completion and unload.
- Keep event queues and retained gameplay state explicitly bounded, and release
  obsolete state on authoritative roster, map, local-team, local-identity, and
  unload transitions.
- Minimize transient tables, strings, repeated formatting, and repeated text
  measurement in the Draw path. Add caching only when all invalidation inputs are
  explicit and tests prove that freshness, screen clamping, dragging, colors,
  and warning-border behavior remain unchanged.
- Do not add a slower polling cadence merely to improve performance unless a
  current observation from `FRAME_NET_UPDATE_END` still reaches the next
  eligible Draw and lifecycle transitions cannot be missed.
- Measure before and after a performance-sensitive change. Use both automated
  call-count/resource-bound tests and a controlled in-game comparison at the
  fullest practical roster size and over a sustained session. Record the test
  environment; do not encode a hardware-specific FPS threshold as a portable
  automated requirement.
- Use `lua tools/benchmark_hot_path.lua` for the repository's repeatable
  32-player capture/Draw comparison. Record its before/after call counts,
  timings, and allocations, but never present those fake-host results as live
  TF2 FPS evidence.

## Testing and verification

- Convert the vectors and matrices in ACCEPTANCE_TESTS.md into executable automated tests wherever the behavior is independent of TF2.
- Use fakes or dependency injection for LMAOBox APIs.
- Run all automated tests after implementation and after later fixes.
- Distinguish automated verification from manual in-game verification.
- Never claim that an in-game test passed unless it was actually run in TF2 with LMAOBox.
- Before finishing, audit every normative specification section and report compliance, test results, and any remaining manual checks.
