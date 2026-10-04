# VoidMark

WoW Forever implementation of VoidMark, based on the supplied working 0.1.5 Forever build and Classic Era commit `fb67dd5` (1.3.10). Classic Era remains a read-only functionality reference.

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

`python tests/validate.py` with `lupa` installed compiles every Lua file under Lua 5.1, parses XML/embedded scripts, verifies the TOC/include graph and packaged assets, and exercises startup plus mocked native kills/deduplication, unconscious/non-group rejection, full-name identity, canonical W/L, loss deduplication, character damage isolation and restricted/secret event handling. These checks cannot prove WoW's secure execution, server event semantics or client rendering.
