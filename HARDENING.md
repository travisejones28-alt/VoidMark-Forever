# VoidMark Forever 1.1.2 — hardening review

Reviewed main at `587aeb6`. The installable addon is the `VoidMarkForever` directory; the older root port is retained for compatibility/reference. No settings, encounter history or pairing consent were reset.

Confirmed fixes:
- Title bars now share their panel's UI layer instead of being forced behind it. The compact tracker remains LOW, beneath normal Nexus/Market panels and the world map.
- A main tracker drag interrupted by hiding the panel now saves its position.
- Raising a window before stack registration no longer follows a nil stack link. Registering a window or initializing its stack twice cannot create a self-cycle.

Both existing copies of the affected Widgets/WindowOrder implementation receive these targeted fixes. Only the current packaged addon's version is advanced; the root legacy port is not presented as the current install target.

Validation: all **90 Lua source files** compile under Lua 5.1; TOC/XML/assets, full mocked startup, feature regressions and isolated sound regressions pass. Added tests cover interrupted drag, title strata, unregistered windows and duplicate registration. The cross-addon Nexus integration also boots the full Forever addon before exercising real Nexus, Mini Map and Market sources.

Installable ZIP: `dist/VoidMarkForever.zip`; the packaging check compares canonical sources including libraries/assets. Run `python -X utf8 tests/validate.py` with `lupa==2.8`.

In-game: open/close and drag the compact tracker; hide it while moving and reload; open its existing settings/context menus; alternate focus among Nexus, Market, stock bags and world map; verify the tracker/title are covered. Existing combat, detection, audio, encounter, gear and manually paired sync behavior require live-client testing; this review did not transmit messages or pair clients. Historical encounter data remains retained rather than being automatically trimmed.

## 1.1.3 header correction

Removed the opaque main-title child backdrop that covered the existing generated artwork. Expanded header geometry to 106 units and repaired the old forced 360-unit width to 430 once. Custom widths and later resizing remain intact. Added regressions for backdrop occlusion, artwork height and width migration. No saved combat data is reset.

## 1.1.4 width adjustment

Expanded default tracker width from 430 to 480 UI units following the Era comparison. A one-time migration widens the old 360/430 defaults, including profiles already migrated by 1.1.3. Other custom widths, height, scale and position remain unchanged. Regression tests cover both upgrade paths, custom widths and subsequent resizing.

## 1.1.5 width adjustment

Expanded the default tracker to 530 UI units. Existing 360/430/480 default widths upgrade once, including profiles updated by 1.1.4. Other custom widths remain saved; tests cover every default upgrade path and subsequent resizing.
