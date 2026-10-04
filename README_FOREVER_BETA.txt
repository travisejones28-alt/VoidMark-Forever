VOIDMARK - WOW FOREVER BETA
Version: 0.1.2-beta-forever
Target: WoW Forever 1.60.1 / Interface 16001

INSTALL
1. Delete/disable any old VoidMark folder in the WoW Forever AddOns directory.
2. Copy the VoidMark folder from this package into the Forever AddOns directory.
3. Turn ON enemy nameplates (V). Forever detection depends on visible unit tokens/nameplates.
4. Log in and run /vmf. It should report Forever=true and interface=16001.
5. /voidmark and /vm are available.

BETA PORT CHANGES
- Addon folder and TOC renamed to VoidMark.
- Interface set to 16001.
- All hard-coded asset paths now point to Interface\\AddOns\\VoidMark.
- Forever data is isolated under a "Forever" repository namespace so it does not mix with live Whitemane history.
- Enemy detection uses nameplates, target, focus, and mouseover, with a 1-second visible-unit rescan.
- COMBAT_LOG_EVENT_UNFILTERED is not registered on Forever.
- Standalone PARTY_KILL is used for GankTracker kill credit.
- Death recap is used as a best-effort source for personal loss attribution.
- Visible Stealth/Prowl/Vanish casts can still trigger alerts.
- Unit-returned values are guarded before they are used as table keys/logic where possible.

EXPECTED BETA LIMITATIONS
- Enemies outside visible/nameplate range will not be detected from combat-log activity.
- Assist/DoT death attribution that previously depended on UNIT_DIED/CLEU is reduced; PARTY_KILL is the primary kill signal.
- Threat fight timing based on direct combat-log damage is not available in this first Forever beta.
- Forever beta build 1.60.1.69913 has a reported SavedVariables load/persistence bug across full client restarts. /reload may behave differently from a full exit/relaunch.
- This is a test build. Keep your Era VoidMark/TaliaaVoidMark folder and SavedVariables backed up separately.

TEST FIRST
- /vmf shows Forever=true, interface=16001.
- Target an enemy player -> appears in VoidMark.
- Mouse over an enemy -> appears.
- Walk near enemy players with nameplates on -> detected.
- Kill an enemy player/group kill -> GankTracker increments once.
- Die to a known enemy player -> check whether loss attribution updates.
- /reload -> UI still loads without Lua errors.


0.1.1 beta fixes:
- Fixed Forever SharedUIPanel tab compatibility in VoidMarkStats.xml.
- Added AceGUI checkbox desaturation compatibility.
- Fixed AceConfig tooltip SetText signature for Forever.
- Added C_PvP zone-PVP fallback and extra secret-value guards.
- Hardened target-frame/tooltip UI compatibility.

0.1.3 beta notes:
- Forever secondary names are now preserved as part of player identity.
- Main list displays full "Main Secondary" names.
- Secure row targeting uses the full player-facing name.
- Removed first-name-only identity fallbacks that could merge two Forever players.
- Fixed VoidMarkUI's captured ButtonClicked call signature.
