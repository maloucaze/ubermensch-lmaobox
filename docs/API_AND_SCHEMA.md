# API and item-schema evidence

Documentary verification was most recently reviewed on 2026-09-14.

## LMAOBox API boundary

The current official documentation supports the required runtime surfaces:

- `entities.GetLocalPlayer()`, `entities.FindByClass("CTFPlayer")`, and
  `entities.GetPlayerResources()`;
- `client.GetLocalPlayerIndex()` and `client.GetConVar()`;
- `globals.RealTime()` and optional `globals.TickCount()`;
- optional `clientstate.GetDeltaTick()` compatibility fallback;
- entity validity, class, index, team, alive state, `IsDormant()`, loadout-slot
  lookup, weapon/Medi Gun checks, typed property reads, and typed data-table
  array reads;
- map, console, game-UI, MvM, and round-state queries;
- font, measurement, screen, color, rectangle, and text drawing;
- menu and mouse state;
- FrameStageNotify, Draw, FireGameEvent, and Unload
  registration/unregistration; and
- optional game-directory persistence helpers.

References:

- <https://lmaobox.net/lua/>
- <https://lmaobox.net/lua/Lua_Libraries/entities/>
- <https://lmaobox.net/lua/Lua_Classes/Entity/>
- <https://lmaobox.net/lua/TF2_props/>
- <https://lmaobox.net/lua/Lua_Libraries/client/>
- <https://lmaobox.net/lua/Lua_Libraries/clientstate/>
- <https://lmaobox.net/lua/Lua_Libraries/globals/>
- <https://lmaobox.net/lua/Lua_Constants/>
- <https://lmaobox.net/lua/Lua_Callbacks/>
- <https://lmaobox.net/lua/Lua_Classes/GameEvent/>
- <https://lmaobox.net/lua/Lua_Libraries/gamerules/>
- <https://lmaobox.net/lua/Lua_Libraries/engine/>
- <https://lmaobox.net/lua/Lua_Libraries/draw/>
- <https://lmaobox.net/lua/Lua_Libraries/input/>

LMAOBox explicitly describes dormant entities as not being updated. Their old
netprops are therefore not current measurements. The Entity reference also
warns against retaining entity objects; the runtime copies primitives and uses
server user ids for durable player identity.

The required current-acquisition point is
`E_ClientFrameStage.FRAME_NET_UPDATE_END`. The current LMAOBox callback and
constant documentation explicitly supports FrameStageNotify and identifies
network-update end as stage 4. Draw consumes the resulting state; it is not the
primary network sampling callback. The generated runtime resolves the live enum
member first and keeps numeric stage 4 only as the documented compatibility
fallback. The callback value is
validated as a finite integral stage at the boundary, including numeric-like
native proxy values that do not compare equal to an ordinary Lua number.

During product-runtime validation on 2026-09-13, the active host repeatedly
reached `FRAME_RENDER_START` (stage 5) without delivering an accepted
`FRAME_NET_UPDATE_END` snapshot. The runtime therefore preserves stage 4 as the
preferred capture and uses stage 5 only when no preferred capture preceded it.
The fallback remains after network processing, precedes Draw, is suppressed
when stage 4 works, and emits one compatibility message per load.

Official `globals` documentation defines `TickCount()` as the client tick count,
and official `clientstate` documentation defines `GetDeltaTick()` as the last
received tick. The runtime uses the first valid value as an optional revision
for suppressing repeated stage callbacks that cannot contain a newer gameplay
snapshot. A new revision and a queued event remain immediate. Missing or
malformed revision data fails open to full capture, so this optimization cannot
silently disable acquisition on a host without those optional members.

Product-runtime validation on 2026-09-13 also established that the native draw
boundary requires integer coordinates: passing the fractional x coordinate
derived directly from normalized placement caused `draw.FilledRect` to reject
the value as having no integer representation. The renderer therefore rounds
measured dimensions and converts normalized placement to clamped integral pixels
before any rectangle or text call.

`clientstate.ForceFullUpdate()` is explicitly excluded. Its documentation warns
that it can lag or crash the game, and a full baseline does not require the
server to transmit entities outside Source PVS.

### Global player resource

The TF2 property list exposes these arrays:

- `CPlayerResource`: `m_bConnected`, `m_bValid`, `m_bAlive`, `m_iTeam`, and
  `m_iUserID`;
- `CTFPlayerResource`: `m_iPlayerClass` and `m_iChargeLevel`.

These arrays provide global roster/lifecycle visibility when a player entity is
outside the normal client update set. They do not provide Medi Gun item family,
deployment state, or a general remote exact charge query.

For a non-dormant player, the current entity's team, class, alive state, and
weapon sample override the corresponding resource row. Entity enumeration also
supplements missing rows. This prevents host-specific resource-table indexing or
update skew from downgrading a nearby readable Medic to unknown data.

Valve's published Source 2013 server code sends the Medic percentage as an
8-bit integer only in tournament mode and writes zero otherwise. Current live
LMAOBox behavior differs: in observed ordinary public/casual matches with
`mp_tournament` disabled, `m_iChargeLevel` changed globally
from 0 through 100, followed deployment drains, and continued changing for a
dormant distant Medic. The implementation targets the observed current runtime,
so it accepts a validated 0-through-100 resource integer without a tournament
gate. The value remains approximate and is displayed as `~N%`; no interval is
exposed. Time-to-ready derived from that value is likewise displayed as `~Ns`.
Malformed, unavailable, out-of-range, or unassociated rows are ignored.

Sources:

- <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_player_resource.cpp>
- <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/tf_player_resource.h>
- <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/tf/c_tf_playerresource.h>

### Medi Gun tables and estimation constants

The local player reads `LocalTFWeaponMedigunData.m_flChargeLevel`; nonlocal
Medics read `NonLocalTFWeaponMedigunData.m_flChargeLevel`. Explicit paths avoid
the duplicate property name resolving to the wrong table. Valve describes the
nonlocal table as the lower-precision observer representation.

On the verified host, `entities.FindByClass("CWeaponMedigun")` returned an empty
table in every recorded changed probe snapshot. Steady-state production and
validation capture therefore do not issue that empirically unproductive query.
The required discovery path is current `CTFPlayer` enumeration followed by the
secondary loadout slot of each possible alive Medic, supplemented by that
player's active-weapon handle. Current/resource lifecycle facts exclude players
definitively known to be dead or non-Medics before weapon-handle reads; an
unreadable class or alive field remains conservatively probeable. Active and
loadout observations are associated with owner/resource identity and an
identical handle is classified only once. None of these routes bypasses PVS; a
dormant loadout weapon may remain readable while exposing frozen values.

Family, charge, and deployment reads are independent. Deployment uses
`GetPropBool("m_bChargeRelease")`; a numeric substitute is rejected because live
testing previously showed false states could be misread through integer access.
Failure of this boolean read does not invalidate a successful family or charge
read. The bare `m_flChargeLevel` path produced unrelated values in live testing
and must not be used. The qualified local/nonlocal table paths returned the
expected normalized 0-through-1 values.

The active-weapon handle is the authoritative observation of whether the Medi
Gun is currently equipped. `m_bHolstered` normally agreed, but briefly
contradicted the active handle during a respawn/loadout transition; it may be
used only as corroborating information, never to discard otherwise valid family,
charge, or deployment fields.

Valve's Medi Gun source documents the 40-second Stock base build, weapon-specific
charge-rate attributes, threefold setup building, eight-second base deployment,
and flashing behavior. Product estimation deliberately uses only the fixed
Stock/Kritz ideal build rates, setup multiplier, and standard eight-second
linear drain. It does not model flashing, target health, multiple healers, melee
gains, custom attributes, or a probability distribution.

Source:

- <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_medigun.cpp>
- <https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/basecombatweapon.cpp>

### Events

The FireGameEvent callback supplies server events to Lua. Ubermensch consumes
only lifecycle/inventory events and `player_chargedeployed`. The deployment
event includes `userid` but no family or precise draining percentage. The event
is stored as primitives and applied only to the record with the same server user
id; entity index is not allowed to redirect it to another player. It can anchor
100% before family identification, but comparison remains unavailable until a
supported current or last-known family exists. Current weapon fields always
override event-derived fields independently.

The current client documentation says all game events are already allowed and
that `client.AllowListener()` is deprecated and does nothing. The runtime
therefore registers `FireGameEvent` directly rather than depending on listener
setup.

### Team-number compatibility

TF2 entity/player-resource values follow Valve's `TF_TEAM_RED = 2` and
`TF_TEAM_BLUE = 3`. The current LMAOBox `E_TeamNumber` documentation table has
the labels reversed. Literal 2/3 automated tests protect local-first ownership,
partitioning, labels, charge values, and deployment colors.

### Startup, persistence, and Lua version

Required host members are checked before callbacks register. Callable native
proxies are accepted by presence. Ordinary data, drawing, input, and persistence
calls remain protected at the boundary.
Position storage is optional and cannot disable gameplay behavior.

Callback registration and startup pre-clear call the validated native proxies
directly so LMAOBox retains normal Lua-panel lifecycle ownership; callback
bodies remain independently protected. The Unload callback performs application
cleanup and returns without invoking `callbacks.Unregister`, after which
LMAOBox's script teardown removes its owned callbacks. Explicit application
stops and the next reload remove all stable callback ids directly outside
Unload.

The official documentation does not identify the embedded Lua version. Source
therefore uses Lua 5.1-compatible syntax. Standalone Lua 5.4 is suitable for
development checks but does not prove live host compatibility.

### Match-validation-only APIs

The separate development validator uses two additional documented surfaces. The
official constants table defines `E_ButtonCode.KEY_F8`/`KEY_F8` as integer 99,
and `input.IsButtonPressed(button)` supplies its edge-triggered manual marker.
`filesystem.CreateDirectory(path)` creates a directory under the TF2 game
directory and returns its full path, which is preferred for validation logs.
The recorder then uses standard Lua `io.open` handles and never writes from the
Draw callback. These APIs are not mandatory capabilities of the ordinary
product runtime beyond input already required for dragging; recorder failure is
isolated from HUD behavior.

References:

- <https://lmaobox.net/lua/Lua_Constants/#e_buttoncode>
- <https://lmaobox.net/lua/Lua_Libraries/input/>
- <https://lmaobox.net/lua/Lua_Libraries/filesystem/>

## Authoritative installed TF2 schema

The family mapping was derived from the installed game file rather than memory
or visible weapon names:

```text
C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\scripts\items\items_game.txt
Last modified (UTC): 2026-07-20T17:46:47.9305837Z
Size: 8,154,015 bytes
SHA-256: 4D1F15B63E63E3E897552CFB8042CCCB99D2E233A0C8D8AFD8734A3EA49D08DA
```

Definitions inheriting `weapon_medigun` or `paintkit_weapon_medigun` are
stock-equivalent. Definitions inheriting `weapon_kritzkrieg` are
Kritzkrieg-equivalent. Other direct `tf_weapon_medigun` mechanics were inspected
separately.

### Stock-equivalent definition indexes

```text
29, 211, 663, 796, 805, 885, 894, 903, 912, 961, 970,
15008, 15010, 15025, 15039, 15050, 15078, 15097,
15120, 15121, 15122, 15145, 15146
```

These cover canonical/Upgradeable stock, Festive 2011, current Botkillers, and
current decorated/war-painted Medi Guns. Renames, qualities, killstreaks, and
Festivizer state do not change the definition index.

### Kritzkrieg-equivalent definition indexes

```text
35
```

All current Kritzkrieg qualities and cosmetic states use definition 35.

### Explicitly unsupported

```text
411 = QUICK-FIX
998 = VACCINATOR
```

Any other Medi Gun definition is unsupported and may leave a never-observed
roster Medic unknown only when no supported current or last-known family exists;
it never receives Stock/Kritz math. Run
`tools/verify_item_schema.ps1` after TF2 item-schema changes and regenerate the
bundle with `tools/build_runtime.ps1 -Deploy`.
