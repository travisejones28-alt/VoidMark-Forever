# VoidMark

WoW Forever implementation of VoidMark. Version 1.1.0 ports the Classic Era changes through `f6e6218`, preserving the working Forever client adapters, complete character identities and existing saved data. Classic Era remains a read-only functionality reference.

## Version 1.1.0

- Settings wheel: **Distract Alert** warns locally when an observed hostile player casts Distract. Readable visible-unit spell events work without combat-log access; readable combat-log casts also work. Duplicate observations share a three-second cooldown. Distract is ground-targeted, so the warning says it was used without claiming you were affected. The alert has its own module to avoid GankTracker's Lua 5.1 local-variable limit.
- Settings wheel: **KOS Alert** controls WHO sightings delivered by VoidLink (`VMKOS1` or `VoidMarkKOS_OnWhoResult`). Banners combine names/classes and remain visible for ten seconds. Group matches can be shared; guild requester-only results stay private. Reasons are shared only when explicitly enabled. Complete Forever names are required; a matching primary name alone is insufficient. `/vmkos` shows options; `on/off`, `share on/off`, `reasons on/off`, `sound on/off`, and `cooldown 30..1800` configure them.
- Kill Effects now separates normal 1–2 kill sounds from 3+ multi-kill sounds. Feign cancels only that victim's recent sound, using GUIDs or complete names. Sounds resolve from the installed VoidMarkForever folder.
- Damage Records has a **POPUP** switch. Hiding banners keeps recording and the existing chat announcements active.
- Enemy Moves uses LOW strata so stock bags and panels cover it. The separate options window keeps its dialog layer.
- Ride or Die retains blocked swaps and checks actual equipment after dismount/Sap recovery before reporting success.
- Gank Repository clears legacy automatic peer links once without changing history. Pairing requires **PAIR on both clients within 14 seconds**, then **SYNC NOW** for history reconciliation. Login/reload clears live session links; repeat manual pairing when needed. Background friend discovery and unsolicited pairing are disabled. KOS party sharing operates separately.
- Carries the PvP assist-credit constant and diagnostic locale fixes. GitHub Actions runs the Forever Lua 5.1 regressions on pushes and pull requests.

## Install and preserve existing data

1. Close WoW. Back up `WTF/Account`.
2. When replacing the old **VoidMark** folder, run `tools/Migrate-VoidMarkSavedVariables.ps1 -ClientRoot 'C:\path\to\your\Forever\client'`. The folder must contain `WTF/Account`. This copies each old `VoidMark.lua` SavedVariables file to `VoidMarkForever.lua` only when the destination does not exist. It retains all originals and never overwrites an existing Forever save.
3. Put the **VoidMarkForever** folder in `Interface/AddOns`, and disable/remove the older VoidMark addon folder so two implementations do not run together. Preserve its SavedVariables backups.
4. Enable VoidMark and enemy nameplates. `/vm` and `/voidmark` remain the main commands; `/vmf` prints client diagnostics. `/spy` is not registered.

The declared account database remains `VoidMarkDB`. Existing Forever history, KOS, preferences and player records retain their namespaces. New RunBack, boats, taunt and gear settings have their own declared storage. Unknown legacy Damage Records ownership is retained in an isolated archive bucket instead of assigned to the current character.

## Systems

Current canonical player/lifetime records, KOS recovery/persistence, account history, group kill credit and deduplication, Today/weekly/session statistics, separate Hunter pet records, GankTracker/minimized view, RunBack/resurrection timers, kill/multikill/streak effects, character-specific highest-hit/crit records, Enemy Moves with group sharing, Sap/Panic alerts, standard friend login/logout alerts, minimap launcher, taunts, ferry synchronization and Ride or Die are included.

The runtime boundary preserves the working Forever visible-unit detection, complete Main-Secondary identity, secure targeting format and native `PARTY_KILL` path. Every addon-owned unit/spell/range API consumer uses readable-value guards. A restricted/secret combat log is discarded; it cannot become a table key, kill credit or damage record. Accepted native kills feed the same repository/statistics/effects and death-time RunBack engine. Enemy casts/auras also feed the existing cooldown tracker when the client exposes readable IDs.

## Client limitations and live validation

- Personal damage records and exact incoming-attacker attribution require readable, attributable combat-log/recap data. The implementation never infers personal damage from target health or another player's hits. If Forever restricts these sources, new personal damage records and some opponent loss attribution are unavailable; existing records/UI remain accessible.
- Enemy cooldowns, potions, Preparation, offensive control spells and Feign notices require readable spell/aura observations. Secret/hidden enemy abilities cannot be reconstructed. Group sharing uses verified roster senders, throttling, duplicate suppression and bounded caches; it cannot reveal information nobody could observe.
- Native Forever `PARTY_KILL` is retained as the baseline's real-death authority. Health zero, unit disappearance and `UNIT_DIED` alone never grant a Hunter kill. Validate actual native credit/Feign ordering on this client.
- RunBack uses death-time location/envelopes and the Classic vanilla map/graveyard network. Live map/graveyard APIs supplement this where readable. Unlocated or changed Forever terrain is treated conservatively; observing a resurrection never calibrates the physical return estimate.
- Ferry cycles and cross-faction taunt translations are carried from Classic; changed Forever travel/language mechanics need live validation. Equip actions still honor combat restrictions.

## Prioritized in-game checks

1. Existing KOS/history survive the filename migration, reload and character swap; different secondary names retain separate identities. Verify initial W/L before killing.
2. Real solo/group player kill counts once in lifetime, Today and session; only the killer announces. Hunter Feign changes no statistics, streak or RunBack timer; a subsequent real kill does.
3. Verify death-position/RunBack countdown, possible-rez color, revival alert and 60-second cleanup in a familiar outdoor zone.
4. Duel Rogue Kidney Shot/Preparation/Vanish, Paladin both bubbles and Mage Ice Block/Barrier; confirm another VoidMark party member receives the same observations on hover.
5. Check Priest/Rogue damage records separately, party versus solo/raid notices, Sap remote alert, Panic visibility, friends, minimap and utility modules.

## Validation

Install the pinned test runtime with `python -m pip install -r tests/requirements.txt`, then run `python tests/validate.py` from the repository root. It compiles every addon Lua file under Lua 5.1, parses XML/embedded scripts, verifies the TOC/include graph and packaged assets, and exercises startup plus mocked native kills/deduplication, unconscious/non-group rejection, full-name identity, canonical W/L, loss deduplication, character damage isolation, restricted/secret event handling, both Distract event paths, KOS matching/privacy/banner timing, explicit pairing and legacy migration, popup settings, frame strata, sound settings/cancellation, and post-Sap equipment recovery. These checks cannot prove WoW's secure execution, server event semantics or client rendering.
