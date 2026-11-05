# Data, mechanics and known limitations

Original data research/build: 2026-09-16. Runtime corrections: 2026-10-04 (VoidMark 1.3.9). Target: Classic Era 1.15.9 / interface 11509.

## Evidence standard

Blizzard UI/API definitions establish available functions and return shapes. They do not publish the live server's graveyard assignment tables, terrain navigation mesh, or enemy resurrection state. Legacy emulators and community route data supply useful reference facts, **not proof of current Era behavior**. No in-game observations were available during this build.

The revision references below document the original data import. This integrated VoidMark repository contains the extracted Lua tables; it does not include the original `Sources/` snapshots, import manifest, rebuild scripts, or standalone coverage CSV. Runtime integration uses VoidMark's player lists and alerts. Questie, Sku and HereBeDragons are not runtime dependencies.

## Primary technical sources

| Source | Revision / use |
|---|---|
| [Blizzard Era UI source mirror](https://github.com/Gethe/wow-ui-source/tree/33e177d9bf38d76d5c6c6e05d5da78db1899659a) | `classic_era` API-generated DeathInfo, Map, MapExploration and Unit definitions. The parallel `classic` branch was inspected initially, then Era definitions were checked. |
| [Questie](https://github.com/Questie/Questie/tree/454b9d072965ee8f1a881429260fcf1fac8d60f7) | Independent DeathInfo annotations; `AreaTable.1.15.7.60277.csv`, `uimapassignment_classic.csv` and UI-map/area mapping references. The available area snapshot is **1.15.7**, not 1.15.9. |
| [CMaNGOS Classic-DB](https://github.com/cmangos/classic-db/tree/22b51464f1625f6ef6275771de1f5466c6f5d19e) | `game_graveyard_zone`, `world_safe_locs`, and spell values from `Full_DB/ClassicDB_1_12_1_z2815.sql.gz`; contemporary graveyard update inspected. Legacy 1.12 reference. |
| [CMaNGOS core](https://github.com/cmangos/mangos-classic/tree/8ec338a1704e7dcb1c0213eb7ed58f9231ade40f) | `GraveyardManager.cpp`, `Corpse.h`, `Player.cpp`: priority, faction, 3D selection, 39-yard radius, ghost spells, reclaim delays. |
| [VMaNGOS core](https://github.com/vmangos/core/tree/8f4e608450460efe1e38743e4da74397d4773a3a) | Independent `ObjectMgr.cpp` area/zone selection, `Player.cpp` ghost form/water walking, `Unit.cpp` 7 yd/s base run speed. |
| [Sku community network](https://github.com/Yennesta/sku-anniversary/tree/b11054c20705888a055e8e64e0eb969d58efd580) | `SkuDB/assets/routedata_global.lua`, `creatures.lua`, `objects.lua`; `SkuNav/Core.lua` explains encoded static junction IDs and coordinates. This is an Anniversary/TBC-maintained network containing older-world data, **not an Era-certified ghost navmesh**. |
| [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons/blob/master/HereBeDragons-2.0.lua) | Independent coordinate-order and UnitPosition restriction cross-check. Code is not bundled or depended upon. |
| [LibRangeCheck](https://github.com/WeakAuras/LibRangeCheck-3.0/blob/main/LibRangeCheck-3.0/LibRangeCheck-3.0.lua) | Positive follow-range checks are approximately 28 yd, with race-specific differences; used only to justify a larger 40 yd uncertainty envelope. No library code copied. |

Attempts to obtain current 1.15.9 WorldSafeLocs/AreaTable exports from wago.tools and wow.tools returned HTTP 403. This was not interpreted as a nonexistent dataset; the build uses the accessible sources with the version mismatch disclosed. Live pin comparison and own-release snapshots are included to identify specific discrepancies.

## API/data findings

### Graveyards

`C_DeathInfo.GetGraveyardsForMap(uiMapID)` returns `GraveyardMapInfo` records with `areaPoiID`, `position`, `name`, `textureIndex`, `graveyardID`, `isGraveyardSelectable`.

It does **not** return faction masks, terrain area assignments, assignment priority, or the graveyard a particular enemy will use. `isGraveyardSelectable` is not proof of enemy eligibility. Empty/nil/error results retain static data. Live pins are used for diagnostic comparison only; they do not add, veto or establish enemy assignment candidates.

Static safe-location IDs are compared to live IDs when equal, and coordinate deltas appear in `/trb gy`. Their equivalence is not assumed proven across every patch. A large delta is a reason to investigate that specific location.

### Areas and map IDs

Terrain `AreaTable.ID`, `ParentAreaID`, UI map ID, and world/continent map ID are different identifiers. The importer preserves these distinctions; world maps 0 and 1 identify EK and Kalimdor in the imported outdoor data.

`C_Map.GetAreaInfo(areaID)` supplies localized names, not the current enemy's area. Observer `GetSubZoneText` is matched only within the known zone parent chain. `C_Map.GetMapInfoAtPosition` returns UI-map details, not an authoritative terrain area ID. `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` returns exploration-area hints; diagnostics may show them, but they are not used as exact enemy terrain-area assignments.

For real deaths with a bounded location and unknown enemy terrain area, candidates include faction-eligible links from every linked subarea of each outdoor UI-map rectangle intersecting the location envelope. Observer area does not restrict these candidates. This is bounded local coverage, not a continent-wide nearest-graveyard search. Rectangles overlap and are not authoritative terrain boundaries, so the union may produce early warnings. Tests and own-player calibration use the known observer area's first eligible parent-chain assignment. An unbounded enemy location produces an immediate warning even if observer links support a displayed prediction.

### Position and units

`C_Map.GetPlayerMapPosition` is documented for the player and party members. An addon cannot assume it works for enemies. `UnitPosition` is also restricted; guarded calls may return nil. No cached, old enemy position is treated as the death point.

World coordinates use the first two `UnitPosition` values in native world/DBC order, matching Sku's `worldX/worldY`. `C_Map.GetWorldPosFromMapPos` returns a continent ID and world vector in corresponding native order. HereBeDragons intentionally swaps these into its own convention; that swap must not be applied to this addon's native-coordinate tables.

For NPC/object junctions in the static network, normalized map coordinates are converted using the imported `UiMapAssignment` rectangular region: world X is derived from vertical map fraction, world Y from horizontal map fraction. This is a legacy rectangular mapping; WMO/microdungeon ambiguities reduce route confidence.

Positive `CheckInteractDistance(unit, 4)` can support a nearby corpse envelope. The build subtracts **40 yd**, larger than the source's approximately 28 yd follow range. This is a conservative modeling allowance, not a verified client-provided coordinate radius. A false, unavailable or throwing check provides **no** bound by itself. A current positive spell-range result or fresh direct-damage envelope may still support a modeled location allowance. Damage fallback anchors on the actual player/party/raid/pet source after validating its GUID; an unavailable source cannot borrow the observer position. Cached envelopes expire after two seconds, and recent samples receive additional movement allowance. Projectile travel, teleportation and exceptional movement remain unverified: these allowances are heuristics, not certified maximum distances. Missing usable geometry produces an immediate warning.

## Selection model and discrepancies

Both examined cores prioritize area links over zone links, filter faction (0 both, 469 Alliance, 67 Horde), and select by squared 3D distance for same-map candidates. CMaNGOS additionally supports map links and global defaults; VMaNGOS's examined area/zone routine can return no match. Neither proves the live Era implementation.

For a known player/test area this addon walks the imported parent chain, taking the first level with eligible links, then predicts the closest same-map candidate. Unknown enemy areas use the local candidate union described above. Graveyard 629 and other test/internal entries are excluded. Faol's Rest remains an eligible Scarlet Monastery vicinity allowance without vetoing other local possibilities. Where height is unavailable the prediction uses 2D; the countdown always uses horizontal distance. It does **not** silently substitute a private-server global default such as Westfall/Crossroads if assignment data is missing.

The referenced contemporary CMaNGOS update removes graveyard 309's instance-area 1477 link; it does not change the outdoor-only extracted set. Starting/near-start subareas and faction-specific capital links in the source are preserved. Special cases absent from that reference remain unverified; there is no claim that all current starting-zone exceptions have been established.

## Movement and resurrection mechanics

The legacy spell data has +25% ground speed for Ghost (8326), and +50% for Night Elf ghost/Wisp (20584); base run speed is 7 yd/s. The model uses the larger applicable speed aura, **8.75** or **10.5 yd/s**, not additive 25% + 50%. Unknown Alliance race uses Wisp speed. Unknown Horde race uses normal speed because Era's Horde races do not include Night Elves.

VMaNGOS explicitly enables water walking for ghost form. Rivers and lakes therefore must not automatically be penalized as living-character swims. Cliffs, steep shorelines, caves, buildings and elevation can still restrict access.

CMaNGOS defines corpse reclaim radius as **39 yd**. This addon subtracts **40 yd** as an earlier-warning allowance rather than claiming an exact live Era 40 yd boundary. It uses a horizontal disk for the floor, deliberately ignoring vertical separation. Diagnostic A* checks where a segment first enters this disk, not just where it reaches the corpse center.

The legacy reclaim-delay model contains 30/60/120-second values, tied to ghost/reclaim state and repeated deaths. The enemy's actual state is not exposed and live Era details were not verified. The build uses zero added delay, never a sum of arbitrary reaction, release and path delays. A future verified unavoidable gate should combine with travel using the correct overlapping clock (`max`, where appropriate), not automatically be added after travel.

Death notification delivery is not the server's exact physical death instant. The addon subtracts measured world RTT when available to bias the warning earlier; remaining latency uncertainty is not eliminated. Later sightings never revise timing or train the model. A safely readable target/nameplate with the exact death GUID and a positive live state may trigger one configured resurrection alert; mouseover remains identity-only. The existing row tick also checks a retained unit token. This observes life state after resurrection; it does not recover the exact server resurrection time.

Soulstones, Reincarnation, friendly resurrection, battle resurrection and other non-corpse-run mechanisms are outside this model and may allow earlier resurrection. A positive timer is never a guarantee that the enemy cannot be resurrected by those means.

## Routing implementation

The importer retains documented source graph links on maps 0/1, resolves encoded NPC/object junctions from the same repository, drops out-of-scope/missing endpoints, filters explicitly named transport waypoints, and rejects cross-continent, zero-length and >250-yard links. The runtime additionally permits up to eight nearby connectors per node within 75 yd in the same zone root. These connectors approximate missing community links and do not prove terrain traversability.

A* uses 2D edge lengths and an admissible geometric heuristic to the 40-yard disk. The start and end can attach to up to three nodes within 80 yd. These endpoint connectors are **unverified**, and source links do not encode every ghost-specific traversal property. The 47,718-node table is allocated only when diagnostics request it. Ordinary kill events do not schedule routes. Explicit searches are incremental, use a binary heap, cache 64 results, cap the queue at 64 jobs, and stop after 60,000 expansions. Removing/replacing a timer or stopping a calibration cancels its queued work. Excessive detours beyond both 250 yd extra distance and 2.25 times the geometric floor are rejected. Disconnected graphs or absent endpoint coverage produce a gap message, not an invented terrain multiplier.

The graph represents community traversals around many obstacles, but it does not certify shortest paths, all bridges, all elevation, one-way cliff behavior, caves, water shortcuts, changed NPC positions or current Era geometry. Sparse connectivity can yield large detours. Therefore graph distance appears **only in details**. The countdown uses a clearly labeled lower bound; it is not misrepresented as the graph's shortest traversable ETA.

No public API in the inspected Era definitions provides an addon-usable all-world navmesh/pathfinding service. A certified shortest-route product would need validated current terrain/collision data and ghost-specific traversal rules, or extensively validated regions whose necessary passages are established. Simply drawing extra nodes would not establish those facts.

## Coverage and priority-zone validation

The extracted map table contains 46 normal outdoor zone/city UI maps; the original `ZONE-COVERAGE.csv` is not included here. The area hierarchy has 970 records; it includes some historical/unused outdoor areas, not a claim that every record is a playable zone.

| Zone | Network nodes incl. subzones | Static graveyards relevant to zone |
|---|---:|---|
| Duskwood | 556 | Darkshire 3 (Alliance), Lakeshire 104 (Horde), Ravenhill 911 (both) |
| Redridge | 932 | Lakeshire 104 (both) |
| Wetlands | 617 | Crossroads 7, Baradin Bay 489 (both) |
| Hillsbrad | 1,122 | Tarren Mill 98 (Horde), Southshore 149 (Alliance) |
| Stranglethorn | 1,734 | Booty Bay 109, Northern Stranglethorn 389 (both) |

These are the imported reference assignments, **not live-server confirmations**. Automated tests check their faction resolution, nearest candidate selection and parent fallback. Real network routes in these five zones were compared with an independent Dijkstra oracle. Agreement validates the A* implementation on the sampled graph, not the real world's terrain or current server assignments.

## Persistence and calibration

Signed remaining times preserve both countdowns and the 60-second post-warning pin across reloads. Nonfinite timer clocks and numeric settings are rejected. Older transient timers are re-evaluated with the corrected candidate rules; unverified legacy combat envelopes become unbounded. Migration may warn earlier but never postpones an existing warning. Permanent player, W/L and kill-history data are unaffected.

Own-player calibration completes on `CORPSE_IN_RANGE`, rather than a horizontal range poll or `PLAYER_UNGHOST`. The observed release start must match the sample's graveyard and be within 80 yd, with a finite positive run and release delay of 0–20 seconds. Invalid, mismatched or older unverified samples remain stored but are excluded from advisory factors and confidence. Confidence counts accepted factors in the selected route/geometric family. No local samples certify another player's path or release behavior, and calibration never changes the displayed geometric countdown.

## License and attribution

This package is distributed under GPL-3.0. CMaNGOS Classic-DB and Sku community data retain their upstream GPL notices; `UPSTREAM-COPYRIGHT.md` preserves Classic-DB's Blizzard-content notice. Questie's exported AreaTable/UI-map facts originate in Blizzard game data. World of Warcraft names and game content belong to Blizzard and its licensors. No endorsement is implied.

Changes made here: outdoor filtering, source-junction decoding, normalized compact Lua tables, new independent addon code, diagnostics, tests and documentation. Reproducible runtime regression and route/Dijkstra checks are included in `tests/`. The original source snapshots and importer are not bundled in this integrated repository; upstream revision links above remain the available provenance references.
