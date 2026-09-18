# Ubermensch LMAOBox - Behavioral Specification

Version 2.4.0
Last updated: 2026-09-17

## 1. Product summary

Ubermensch is a self-contained Lua HUD for Team Fortress 2 running under
LMAOBox. It compares the selected Stock Medi Gun, Kritzkrieg, or Quick-Fix on
the local player's team with the selected comparison-supported Medic on the
opposing team. The Vaccinator has limited display-only support.
Below the Uber comparison, it also reports the current alive-player counts in
local-team-first order without classifying their tactical significance.
In definite 6v6 or 4v4 competitive/tournament play, an optional fifth line
reports enemy Snipers and Spies, including whether at least one is alive.

When the local player is an alive Medic, the local side is that player alone.
Otherwise, including while dead, the script selects the relevant Medic
independently on both teams. The local player's team is always displayed
first.

The widget prioritizes current information whenever it is readable. Global
roster data, server events, retained facts, and deterministic point estimates
keep distant Medics useful. Every resource-derived or estimated numeric
percentage, and every readiness derived from one or from a retained family, is
marked with `~`. No warning border is drawn.

## 2. Normative language

`MUST`, `MUST NOT`, `SHOULD`, `SHOULD NOT`, and `MAY` are normative. Examples
illustrate these rules and do not override them.

## 3. Scope

### 3.1 Included

- Full Stock Medi Gun, Kritzkrieg, and Quick-Fix comparison support.
- Display-only Vaccinator family and charge support.
- Current local, allied, and enemy charge and deployment observations when readable.
- Global RED/BLU roster, class, alive, and user-id data from player resources.
- Validated global player-resource charge samples.
- Relevant lifecycle and charge-deployment events.
- Continuous point estimates derived from the last trustworthy observation.
- Alive self-Medic and team-comparison modes.
- Active-first Medic selection and nearest-time-to-ready normal selection.
- A fixed four-line, local-team-first, draggable HUD with a visual separator
  between the Uber comparison and alive-player counts, plus an optional
  separately divided enemy off-class line in definite 6v6/4v4 play.
- Enemy Sniper and Spy counts with alive/dead presentation in definite 6v6 and
  4v4 competitive/tournament formats.
- Persistent normalized position.

### 3.2 Excluded

- Vaccinator readiness, comparison math, estimation, and deployment display.
- Unknown/custom Medi Gun readiness, comparison math, and estimation.
- Tactical valuation of invulnerability versus critical hits.
- Mann vs. Machine and nonstandard playable teams.
- Modified weapon-balance attributes or server-specific charge rates.
- Forecasting future healing targets, deaths, respawns, or weapon switches.
- Discrete melee charge gains such as an Ubersaw hit.
- Sound, chat, notifications, automation, network requests, or gameplay writes.
- User-editable runtime configuration.
- Charge intervals, probabilistic estimates, or an `UNCERTAIN` status.
- Forcing network updates or attempting to defeat Source PVS/dormancy.
- Off-class reporting in casual, Highlander/9v9, unsupported, or uncertain
  match formats, and classes other than Sniper and Spy.

## 4. Terms and data certainty

### 4.1 Medic candidates and support levels

A living Medic candidate is alive and is actually class Medic. Disguised Spies
are not Medics. Stock, Kritzkrieg, and Quick-Fix are comparison-supported
families. Vaccinator is a recognized display-only family. An unidentified or
custom Medi Gun remains an unknown-family fallback rather than making its
Medic disappear.

Every globally known living Medic MUST prevent a false `NO MED`. A recognized
comparison-supported candidate outranks Vaccinator and unknown/custom
fallbacks in team mode as specified in Section 7. This support-tier ordering
does not apply in self-Medic mode: an alive local Medic is always shown,
including while using Quick-Fix, Vaccinator, or unknown/custom equipment.

When no living Medic exists, any authoritatively dead Medic is represented by
the separate `DEAD MED` fallback. This fallback MUST never outrank a living
Medic, including one whose family or charge is still unknown.

### 4.2 Current field observations

Family, charge, and deployment are independent observations. A field is exact
when it is successfully validated from a current non-dormant Medi Gun. Failure
to read one field MUST NOT discard another valid current field from the same
weapon. In particular, an unreadable deployment boolean MUST NOT cause a valid
changing charge percentage to be replaced by retained or estimated data.

The local alive Medic uses the local Medi Gun charge table. Other Medics use the
nonlocal table. Acquisition MUST enumerate current `CTFPlayer` entities for
lifecycle validation. It MUST inspect the secondary loadout slot of every
non-dormant player whom current or resource data identifies as a possible alive
Medic. A player whose class or alive state is unreadable remains possible and
MUST still be inspected; a player definitively known to be dead or a non-Medic
MUST NOT incur weapon-handle inspection. The active-weapon handle supplements
the secondary slot. Duplicate active/loadout observations of the same weapon and
owner MUST be reconciled into one record. Steady-state acquisition MUST NOT
perform direct `CWeaponMedigun` enumeration: reviewed live evidence returned no
results, while the per-player loadout path provides the required discovery.

Dormant netprops MUST NOT be labeled current because LMAOBox states that dormant
entities are not being updated. A visible player model alone does not prove that
every weapon field is readable, but every field that is readable and valid MUST
be consumed. Current observations MUST be captured after network updates at
`FRAME_NET_UPDATE_END` for each new validated revision, or whenever that stage
is delivered if no revision is available. A host that omits stage 4 but reaches
`FRAME_RENDER_START` MUST use stage 5 as the compatibility capture point. A
successful stage-4 callback MUST suppress the immediately following
stage-5 fallback so acquisition occurs at most once across that callback pair.
When the host exposes a validated client/network tick revision, repeated
preferred or fallback stages for the same revision MUST NOT reacquire the full
snapshot unless a relevant event is queued. A changed revision and a queued
event MUST be reconciled immediately. If the revision is unavailable or
malformed, acquisition MUST fail open by capturing rather than risk stale data.
Every actual capture MUST reach the next eligible Draw; Draw itself MUST NOT
reacquire the network snapshot.

### 4.3 Player-resource sample

Player-resource identity arrays are the preferred global roster authority.
They determine connected/valid membership, entity index, server user id, team,
class, and alive state even when an entity is outside the normal update set.

Current LMAOBox live evidence shows `m_iChargeLevel` updating globally from 0
through 100 in ordinary casual/public matches with `mp_tournament` disabled,
including while a Medi Gun entity is dormant. A readable integer `N` in the
inclusive range 0 through 100 from a validated, connected Medic resource row is
therefore a trustworthy but approximate point anchor at `N%` in any supported
match and is displayed with `~`. It MUST NOT be gated on `mp_tournament`.
Malformed, out-of-range, unavailable, or unassociated resource values MUST be
ignored. Resource arrays are indexed at Lua table index `entity index + 1`.

### 4.4 Event-derived sample

The script consumes `player_spawn`, `player_death`, `player_changeclass`,
`player_team`, `post_inventory_application`, and `player_chargedeployed`.
Events update or invalidate tracked facts but never override a current field
observation from the same network cycle. `player_chargedeployed` proves a 100%
conventional deployment at its event time only after that Medic is known to use
Stock, Kritzkrieg, or Quick-Fix; it does not identify an unseen Medi Gun family.
A pending event MUST be ignored if the Medic is identified as Vaccinator or
unknown/custom because the event does not expose Vaccinator segment state.

Every deployment event MUST be resolved through its `userid` and applied only to
the matching Medic record. It MUST NOT be applied team-wide, to whichever Medic
is currently selected, or to a different Medic with a reused entity index. An
event for a known but currently unselected Medic updates that Medic and may
affect later selection.

Event and player-resource state MUST be keyed by server user id when available,
with entity index only as a fallback. No raw entity or event object may be kept
between frames.

### 4.5 Trustworthy anchors and point estimates

A charge anchor is the most recent trustworthy charge fact for one Medic:

- a current validated charge field;
- a validated player-resource charge;
- 100% at a correctly associated conventional `player_chargedeployed` event; or
- 0% at spawn or post-inventory application while retaining a last-known family.

An estimate is a single deterministic point calculated from that immutable
anchor and elapsed monotonic time. A prior estimate MUST NOT become a new anchor;
recomputing from the original anchor prevents cumulative frame-to-frame drift.

For an inactive charge:

```text
estimate = min(100, anchor charge + family rate * phase multiplier * elapsed)
```

Stock's fixed rate is 2.5 percentage points per second, Kritzkrieg's is 3.125,
and Quick-Fix's is 2.75. Preround/setup elapsed time uses multiplier 3; all
other comparison-supported time uses multiplier 1. If an estimate crosses a
known phase transition, the elapsed segments MUST be integrated with their
respective multipliers. Vaccinator and unknown/custom charge MUST NOT be
estimated; only a current or valid resource percentage may be displayed.

For a deployed charge, the standard eight-second linear drain is used:

```text
drain rate = 100 / 8 = 12.5 percentage points per second
drain duration = anchor charge / 12.5
```

Before the drain duration expires, estimated charge is
`max(0, anchor charge - 12.5 * elapsed)` and deployment remains estimated active.
Afterward, estimated deployment is inactive and ideal building begins from 0%
for the remaining elapsed time. Flashing acceleration is not modeled.

An estimate reaching 100% remains there until a trustworthy deployment, death,
spawn, inventory, or current/resource observation changes its anchor. Every
estimated or resource-derived percentage is displayed with `~`. Current
information immediately replaces the estimate, even
when the correction is large.

### 4.6 Missing, dead, and unknown

`NO MED` means a complete current roster proves there is no Medic-class player
on that side. `DEAD MED` means at least one Medic is authoritatively dead and no
living Medic exists, regardless of the dead Medic's known family. Both are
fixed at 0% for comparison and omit time-to-ready. `DEAD MED` follows its
identity through a team change while the player remains a Medic, and remains
until that identity respawns, changes away from Medic, disconnects, or match
state is reset.

Unknown state is field-local: family is `UNKNOWN`
only when that Medic has no current or last trustworthy family, and charge is
`?%` only when there is no current charge or trustworthy charge anchor. Thus a
valid current charge with unreadable family may render
`RED | 63% | - | UNKNOWN`, while a known family without a charge anchor
may render `RED | ?% | - | STOCK`. A complete unknown state is expected
only when neither fact has ever been available,
such as immediately after joining a match. Unknown charge is never fabricated as
zero.

Once a comparison-supported family and charge anchor exist, loss of visibility MUST produce
a continuing estimate rather than `UNKNOWN`, regardless of its age. A verified
family remains last-known through distance, spawn, and post-inventory
application and is replaced immediately by contradictory current weapon data.
Map change, disconnect, server-user-id change, confirmed non-Medic class, and
confirmed unknown/custom weapon evidence clear incompatible retained family and
estimation facts without removing the living Medic candidate.

## 5. Comparison math

For a current or estimated percentage `C` and family ideal rate `R`:

```text
time-to-ready = max(0, 100 - C) / R
charge difference = local-side charge - enemy charge
time difference = enemy time-to-ready - local-side time-to-ready
```

Each normal team line displays its own time-to-ready before the family. It is calculated
from the selected side's unrounded family and charge through this same formula,
then rounded half away from zero to a whole number of seconds. It has no sign.
Readiness is prefixed with `~` when its charge is resource-derived or estimated,
or when its charge rate depends on a retained family. A confirmed `NO MED` or
a side lacking either a comparison-supported family or numeric charge displays `-` instead
of fabricating readiness. Deployment does not select another readiness formula;
the current or estimated charge continues through the formula above.

Positive differences favor the local side. Status uses full precision:

- `ADV` when time difference is greater than 10 seconds;
- `DIS` when it is less than -10 seconds;
- `EQL` from -10 through +10 seconds, inclusive.

With exactly one known comparison-supported side and one unavailable side (`NO MED` or
`DEAD MED`), the known side is `ADV` or `DIS`, charge difference is shown, and
the time field is `-`. Two unavailable sides are `EQL | 0% | -`.

Estimated point values use exactly the same formulas and `ADV`/`DIS`/`EQL`
thresholds as current values. If any input used by a displayed difference is
approximate, estimated, or retained, the numerical differences are prefixed
with `~`. There is no `UNCERTAIN` status. If either selected side lacks the
family or numerical charge needed for comparison, the entire third line is
exactly `-`.

### 5.1 Alive-player counts

The fourth line compares the number of connected, valid, alive players on the
local team with the corresponding number on the enemy team. Every playable
class counts; spectators, unassigned players, disconnected slots, invalid
resource rows, and dead players do not. The local count is always shown first.

Counts MUST be derived from each complete authoritative roster reconciliation.
Valid current entity lifecycle fields overlay lagging resource lifecycle fields
before counting. Relevant events force the next reconciliation, but event-only
arithmetic MUST NOT replace the authoritative roster calculation. Counting MUST
reuse the existing linear roster/tracking work and MUST NOT introduce another
polling loop, candidate sort, or nested full-roster scan.

When complete roster authority or either count is unavailable, the fourth line
MUST be exactly `- vs. -`. Otherwise it is exactly
`<LOCAL_ALIVE> vs. <ENEMY_ALIVE>`. The line is always ordinary white and MUST
NOT contain `ADV`, `DIS`, `EQL`, a threshold, percentage, ratio, or any other
classification. Last-known player counts MUST NOT be retained or presented as
current.

### 5.2 Enemy off-class detection

The optional fifth line reports connected, valid enemy Snipers and Spies in
definite 6v6 or 4v4 competitive/tournament play. Alive and dead players both
contribute to the displayed class count. Spectators, unassigned players,
disconnected slots, invalid rows, and the local team do not. Detection MUST use
the complete authoritative roster and MUST be omitted when roster authority is
unavailable.

Casual play MUST always suppress the feature. A validated competitive match
type or enabled `mp_tournament` is required. The configured visible player-slot
count is preferred: 12 total slots identifies 6v6 and 8 identifies 4v4. An
explicit 18-slot, `mp_highlander`, or any other valid unsupported capacity MUST
be suppressed. Only when the slot count is missing, malformed, zero, or
negative may the current complete roster infer the format from the
larger RED/BLU team count, including dead players: exactly 4 identifies 4v4,
5 or 6 identifies 6v6, below 4 is unknown, and above 6 is unsupported. This
fallback intentionally prevents an observable 9v9 roster from being treated as
6v6.

The line is omitted when the format is not definite or neither tracked class is
present. Otherwise it begins exactly `Off-class: ` and lists `SNIPER` before
`SPY`, omitting absent classes. Duplicate instances use ` (N)`, for example
`Off-class: SNIPER (2), SPY`. A class token is white when at least one detected
player of that class is alive and gray only when every detected player of that
class is dead. The prefix, comma, and spaces remain white. Roster changes,
including death, respawn, connect, reconnect, disconnect, team change, and
class change, MUST update the next resolved display without a separate polling
cadence.

## 6. Source and state precedence

For each network update, precedence is applied independently to family, charge,
deployment, and roster/lifecycle fields:

1. Validate gameplay context and local identity.
2. Apply queued relevant events in order.
3. Reconcile global player-resource roster facts.
4. Overlay every valid current entity/weapon field independently.
5. Use fresh validated player-resource charge only where current charge is
   absent.
6. Use last-known family only where current family is absent.
7. Derive a point estimate from the last trustworthy anchor only where current
   or resource charge is absent.
8. Use `UNKNOWN` only when no current or last trustworthy information can produce
   the required family and number.
9. Use `DEAD MED` only when no living Medic candidate exists and authoritative
   lifecycle data proves at least one Medic is dead.
10. Use `NO MED` only when the global roster proves no Medic-class player is on
    that team and no dead-Medic fallback applies.

Current fields always win. Resource values, events, retained facts, and
estimates fill missing fields only and MUST NOT replace a current valid field.
A read failure for one field cannot downgrade another valid field.

Spawn and post-inventory events anchor charge at 0% and mark a known family
as last-known until re-observed. Team and class changes invalidate incompatible
state. Death removes eligibility and clears charge/deployment while retaining a
known family when available; a subsequent spawn clears the fallback and
establishes the new 0% anchor. Class change away from Medic, disconnect,
map/session reset, and identity replacement clear an incompatible dead
fallback. A team change moves the dead Medic fallback to the new team while the
player remains class Medic and clears incompatible weapon/charge state.
Disconnect, map change, local-team change, local-player change, and unload clear
affected tracking state. Moving between self-Medic and team-comparison mode
changes selection but MUST NOT erase still-valid records for other Medics.
Brief overlay suppression does not erase valid tracking state.

When player resources are temporarily unreadable, previously tracked players
MAY remain represented with retained/estimated marking. A failed global roster
read MUST NOT prove `NO MED`.

## 7. Medic selection

Only one Medic is displayed per side.

If the local player is an alive Medic, that player is the local-side candidate
and every other allied Medic is ignored. Otherwise, alive allied and enemy
rosters are selected independently.

Any comparison-supported candidate whose current or estimated deployment is active
outranks non-active candidates. Active candidates rank by greatest current or
estimated remaining charge. Normal candidates rank by earliest current or
estimated time-to-ready. Source freshness is a tie-breaker, not a reason to
discard a useful estimate. Outside the tie tolerances, the better numerical
candidate always wins. Within a 0.05-second normal tie, family preference is
`STOCK`, then `KRITZ`, then `QF`; current data then outranks resource data,
which outranks an estimate. Within a 0.1-percentage-point active tie there is no
family preference, and the same source freshness order applies directly.
Remaining ties retain the prior server user id, then use the lowest entity
index.

Team-mode selection uses these support tiers in order: a numeric
comparison-supported candidate; a comparison-supported candidate lacking a
numeric charge; Vaccinator; unknown/custom. A higher tier always outranks a
lower tier. Among Vaccinator candidates, the greatest known current/resource
charge wins, followed by the ordinary freshness, prior-user-id, and entity-index
tie-breaks. Unknown/custom Medics are never excluded from representation. If no
living Medic exists, a retained dead Medic is selected: the previously selected
server user id wins, otherwise the most recent authoritative death wins, then
lowest entity index breaks an exact tie. Confirmed invalidation triggers immediate reselection. A
deployment event updates only its matched Medic record; if that
Medic becomes the highest-priority active candidate, normal selection may then
select that Medic.

## 8. HUD content and formatting

The widget always uses four base text lines during supported gameplay. A
one-pixel horizontal separator divides the first three Uber lines from the
fourth alive-player-count line. In the definite competitive formats specified
by Section 5.2, a second separator and optional fifth line appear only while an
enemy Sniper or Spy is detected:

```text
<LOCAL_TEAM> | <LOCAL_CHARGE> | <LOCAL_TIME> | <LOCAL_FAMILY>
<ENEMY_TEAM> | <ENEMY_CHARGE> | <ENEMY_TIME> | <ENEMY_FAMILY>
<STATUS>     | <CHARGE_DIFFERENCE> | <TIME_DIFFERENCE>
<LOCAL_ALIVE> vs. <ENEMY_ALIVE>
[separator and `Off-class: ...` only when applicable]
```

Examples:

```text
RED |  75% |   8s | KRITZ
BLU |  50% |  20s | STOCK
ADV | +25% | +12s
8 vs. 3
Off-class: SNIPER (2), SPY
```

```text
RED |  ~88% |  ~5s | STOCK
BLU |   73% |   9s | KRITZ
EQL | ~+15% | ~+4s
8 vs. 12
```

```text
RED | ?% | - | UNKNOWN
BLU | NO MED
-
- vs. -
```

Confirmed death uses the same compact unavailable layout:

```text
RED | DEAD MED
```

The local player's team is first. Team labels are `RED` and `BLU`. Family
labels are `STOCK`, `KRITZ`, `QF`, `VACC`, or `UNKNOWN`; unavailable labels are `NO MED` and
`DEAD MED`. Medic player names and additional Medic labels are never shown.

Current percentages are whole numbers. Resource-derived and estimated percentages use
`~N%`. No percentage interval is shown. Unknown charge uses `?%`. Team-line
readiness uses whole seconds, uses `~Ns` when approximate, and otherwise uses
`Ns`; Vaccinator and unavailable readiness are exactly `-`. Percentage and time columns are
right-aligned to the widest displayed token across the normal team lines and
comparison line. Compact `NO MED` and `DEAD MED` lines do not participate in
column sizing. Each separator has exactly one padding space on each side;
additional leading spaces inside numeric cells exist only for right alignment.

Signed percentage and time differences use whole numbers. Approximate
differences use a leading `~`. Positive nonzero values use
`+`; displayed zero has no sign; negative zero is normalized. Calculations and
classification occur before display rounding.

All text MUST be printable ASCII. Deployment does not change text or stop
comparison updates. The alive-player line is not padded to the Uber numeric
columns and uses exactly one space around `vs.` as shown. The optional
off-class line is not padded to either preceding layout.

## 9. Colors

| Role | RGBA |
|---|---|
| Advantage | `(80, 220, 120, 255)` |
| Disadvantage | `(235, 80, 80, 255)` |
| Equal / ordinary text | `(255, 255, 255, 255)` |
| Guaranteed ready | `(255, 235, 60, 255)` |
| RED deployed | `(255, 80, 80, 255)` |
| BLU deployed | `(80, 160, 255, 255)` |
| Unavailable Medic | `(170, 170, 170, 255)` |
| Background | `(15, 15, 18, 170)` |

Alive-player presentation uses separate fixed constants from the Uber palette:

| Team-count role | RGBA |
|---|---|
| Text, including unavailable | `(255, 255, 255, 255)` |
| Separator | `(170, 170, 170, 255)` |

Off-class presentation uses separate fixed constants:

| Off-class role | RGBA |
|---|---|
| Prefix, punctuation, alive class | `(255, 255, 255, 255)` |
| Class with every detected instance dead | `(170, 170, 170, 255)` |

The entire third line uses its status color; `-` uses ordinary white. A team line
uses its deployed team color while current or event/estimate-derived conventional
deployment is active, otherwise yellow when its current or estimated charge is
100%, otherwise white. Vaccinator ignores deployment state and is yellow at
25% or greater, otherwise white. `NO MED` and `DEAD MED` lines are gray.
The fourth line always uses its independent ordinary-white team-count color.
The fifth-line prefix and punctuation are white. Each Sniper or Spy token is
white when any represented player of that class is alive and gray only when
all represented players of that class are dead. The widget MUST NOT draw a
data-quality warning border in any state; `~`, `?`, and `-` carry data-quality
meaning in text.

The widget uses the fixed-width Lucida Console face at size 14, weight 600,
antialiasing, six pixels horizontal and four pixels vertical padding, one pixel
between the three Uber lines, three pixels above and below each one-pixel
separator, and the fixed background. Each separator spans the content width
inside the horizontal padding. The fixed-width face makes the padded numeric
columns visually align. There is no animation, blinking, pulsing, or sound.


## 10. Positioning and persistence

The default top-left normalized position is `(0.02, 0.35)`. The whole measured
widget MUST remain on-screen and be reclamped after resolution or text changes.
Normalized positions and measured dimensions MUST be converted to integral
pixel coordinates before any LMAOBox drawing call; fractional coordinates MUST
NOT cross the drawing boundary.
It can be dragged only while the LMAOBox menu is open, beginning on a left press
inside the widget and preserving pointer offset. Dragging ends on release or
menu close and MUST NOT capture or synthesize input.

Position is strictly parsed and versioned. Preferred storage is
`%LOCALAPPDATA%\lua\ubermensch_position_v1.txt`; fallback storage is
`<TF2 game directory>/ubermensch-lmaobox/ubermensch_position_v1.txt`. If neither
works, the HUD continues in memory and emits exactly one concise warning per
load. Saves occur on drag completion and unload, not every frame.

## 11. Visibility and lifecycle

The widget is visible during ordinary pregame, startgame, preround/setup, and
running states, including while the local player is dead or a side has no
Medic. It is hidden during team-win, restart, stalemate, game-over,
bonus, between-round, MvM, absent-map, Source-console, and TF2-game-UI states.
Scoreboard, chat, and the LMAOBox menu do not hide it. There is no screenshot
special case.

Callback identifiers MUST be stable across releases so reloads replace prior
callbacks. Queued events MUST be bounded to 64 entries. On unload, the script
ends dragging, saves dirty position when possible, clears transient tracking,
and unregisters FrameStageNotify, Draw, FireGameEvent, and Unload callbacks.

## 12. Error handling and performance

All mandatory host capabilities are validated before registration. Missing
capabilities stop initialization and are each printed once after:

```text
[Ubermensch] required LMAOBox API unavailable:
[Ubermensch] missing: <CAPABILITY>
```

Callable host proxies are accepted. Malformed host values fail closed without
an uncaught per-frame error. Expected distance/dormancy is silent. An unexpected
FrameStageNotify, Draw, or event-processing fault emits one concise warning and
disables only that callback path for the load.

For `P` available player slots, network-stage snapshot, reconciliation,
alive-player counting, off-class summarization, and selection work MUST remain
`O(P)` per update. Selection MUST NOT require sorting. Both roster summaries
MUST be folded into an existing roster/tracker pass rather than adding a
separate full-roster pass.
Draw consumes the latest resolved display state. A newly readable current field
at the preferred `FRAME_NET_UPDATE_END`, or at the authorized
`FRAME_RENDER_START` fallback when stage 4 is absent, MUST be reflected on the
next successful eligible Draw; performance work MUST NOT add a stale polling
interval or weaken Section 6.

Known dead and non-Medic players MUST be excluded before active/loadout weapon
inspection, while unreadable lifecycle fields MUST remain conservatively
probeable. Duplicate frame-stage callbacks for a validated unchanged tick MUST
perform no roster/entity acquisition. This duplicate suppression is event-aware
and MUST fail open when its optional revision source is unavailable.

The font MUST be created once during initialization and reused. Each successfully
rendered eligible base frame MUST draw exactly one widget: one background
rectangle, one separator rectangle, and four text calls. A visible off-class
line adds exactly one separator rectangle and one text call per fixed-color
segment: prefix, each present class token, and the comma when both classes are
present. No border rectangles are drawn. Ordinary steady-state Draw processing
MUST NOT perform file I/O, schema
inspection, network access, or routine console logging. Position storage may be
written only when a drag completes or during unload as specified in Section 10.
When the menu is closed and no drag is active, Draw MUST NOT query mouse
position or button states. Unchanged formatted text and measured layout storage
SHOULD be reused when all observable invalidation inputs are unchanged.

The event queue MUST remain bounded to 64 entries. Retained gameplay memory MUST
contain only primitive domain data, MUST be cleared on the lifecycle transitions
defined in Sections 6 and 11, and MUST NOT grow on repeated frames with an
unchanged roster. Transient allocations SHOULD be kept proportionate to this
small HUD, but reducing allocations or caching formatted/layout data MUST NOT
change observable output, update freshness, estimate anchors, dragging, or error
behavior.

## 13. Runtime and verification contract

`ubermensch.lua` MUST be a self-contained generated runtime with no external Lua
module dependency. Authored behavior MUST remain testable outside TF2 through
pure functions and faked LMAOBox boundaries. Automated checks cover all
practical vectors; actual host netprops, distance transitions, and rendering
remain manual in-game acceptance requirements and MUST NOT be claimed when not
performed.

Performance-sensitive changes MUST be measured with the repository's
deterministic full-roster benchmark before and after implementation. Its desktop
timings and allocation counts are comparative development evidence only; actual
FPS and frame-time effects remain manual in-game requirements.

## 14. Authoritative references

- LMAOBox Lua documentation: <https://lmaobox.net/lua/>
- Entity and player-resource APIs: <https://lmaobox.net/lua/Lua_Libraries/entities/>
- Entity methods and dormancy: <https://lmaobox.net/lua/Lua_Classes/Entity/>
- TF2 properties: <https://lmaobox.net/lua/TF2_props/>
- Client library: <https://lmaobox.net/lua/Lua_Libraries/client/>
- Client-state library: <https://lmaobox.net/lua/Lua_Libraries/clientstate/>
- Predefined frame-stage constants: <https://lmaobox.net/lua/Lua_Constants/>
- Callbacks and GameEvent: <https://lmaobox.net/lua/Lua_Callbacks/>
- Valve `CTFPlayerResource`: <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_player_resource.cpp>
- Valve Medi Gun behavior: <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_medigun.cpp>
- Valve owned-weapon transmission: <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/basecombatweapon.cpp>
- TF2 Wiki, UberCharge: <https://wiki.teamfortress.com/wiki/%C3%9CberCharge>
