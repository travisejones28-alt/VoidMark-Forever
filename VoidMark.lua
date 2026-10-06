local SM = LibStub:GetLibrary("LibSharedMedia-3.0")
local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale("VoidMark")
local fonts = SM:List("font")
local _

VoidMark = LibStub("AceAddon-3.0"):NewAddon("VoidMark", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
VoidMark.Version = "0.1.5-beta-forever"
VoidMark.DatabaseVersion = "1.1"
VoidMark.Signature = "[VoidMark]"
VoidMark.ButtonLimit = 15
VoidMark.MaximumPlayerLevel = (MAX_PLAYER_LEVEL_TABLE and MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()]) or 60

VoidMark.ZoneID = {}
VoidMark.KOSGuild = {}
VoidMark.CurrentList = {}
VoidMark.NearbyList = {}
VoidMark.LastHourList = {}
VoidMark.ActiveList = {}
VoidMark.InactiveList = {}
VoidMark.ListAmountDisplayed = 0
VoidMark.ButtonName = {}
VoidMark.EnabledInZone = false
VoidMark.InInstance = false
VoidMark.AlertType = nil
VoidMark.UpgradeMessageSent = false
VoidMark.zName = ""
VoidMark.ChnlTime = 0
VoidMark.Skull = -1
VoidMark.PetGUID = {}

-- Localizations for VoidMarkStats
L_STATS = "VoidMark "..L["Statistics"]
L_WON = L["Won"]
L_LOST = L["Lost"]
L_REASON = L["Reason"]
L_LIST = L["List"]
L_TIME = L["Time"]
L_FILTER = L["Filter"]..":"
L_SHOWONLY = L["Show Only"]..":"

VoidMark.options = {
	name = L["VoidMark"],
	type = "group",
	args = {
		About = {
			name = L["About"],
			desc = L["About"],
			type = "group",
			order = 1,
			args = {
				intro1 = {
					name = L["VoidMarkDescription1"],
					type = "description",
					order = 1,
					fontSize = "medium",
				},	
				intro2 = {
					name = L["VoidMarkDescription2"],
					type = "description",
					order = 2,
					fontSize = "medium",
				},
				intro3 = {
					name = L["VoidMarkDescription3"],
					type = "description",
					order = 3,
					fontSize = "medium",
				},
			},
		},
		General = {
			name = L["GeneralSettings"],
			desc = L["GeneralSettings"],
			type = "group",
			order = 1,
			args = {
				intro = {
					name = L["GeneralSettingsDescription"],
					type = "description",
					order = 1,
					fontSize = "medium",
				},
				EnabledInBattlegrounds = {
					name = L["EnabledInBattlegrounds"],
					desc = L["EnabledInBattlegroundsDescription"],
					type = "toggle",
					order = 2,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.EnabledInBattlegrounds
					end,
					set = function(info, value)
						VoidMark.db.profile.EnabledInBattlegrounds = value
						VoidMark:ZoneChangedEvent()
					end,
				},
--[[				EnabledInArenas = {
					name = L["EnabledInArenas"],
					desc = L["EnabledInArenasDescription"],
					type = "toggle",
					order = 3,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.EnabledInArenas
					end,
					set = function(info, value)
						VoidMark.db.profile.EnabledInArenas = value
						VoidMark:ZoneChangedEvent()
					end,
				},
				EnabledInWintergrasp = {
					name = L["EnabledInWintergrasp"],
					desc = L["EnabledInWintergraspDescription"],
					type = "toggle",
					order = 4,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.EnabledInWintergrasp
					end,
					set = function(info, value)
						VoidMark.db.profile.EnabledInWintergrasp = value
						VoidMark:ZoneChangedEvent()
					end,
				}, 
				EnabledInSanctuaries = {
					name = L["EnabledInSanctuaries"],
					desc = L["EnabledInSanctuariesDescription"],
					type = "toggle",
					order = 5,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.EnabledInSanctuaries
					end,
					set = function(info, value)
						VoidMark.db.profile.EnabledInSanctuaries = value
						VoidMark:ZoneChangedEvent()
					end,
				}, ]]--
				DisableWhenPVPUnflagged = {
					name = L["DisableWhenPVPUnflagged"],
					desc = L["DisableWhenPVPUnflaggedDescription"],
					type = "toggle",
					order = 6,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.DisableWhenPVPUnflagged
					end,
					set = function(info, value)
						VoidMark.db.profile.DisableWhenPVPUnflagged = value
						VoidMark:ZoneChangedEvent()
					end,
				},
				DisabledInZones = {
					name = L["DisabledInZones"],
					desc = L["DisabledInZonesDescription"],
					type = "multiselect",
					order = 7,
					get = function(info, key) 
						return VoidMark.db.profile.FilteredZones[key] 
					end,
					set = function(info, key, value) 
						VoidMark.db.profile.FilteredZones[key] = value 
					end,
					values = {
						["Booty Bay"] = L["Booty Bay"],
						["Everlook"] = L["Everlook"],
						["Gadgetzan"] = L["Gadgetzan"],
						["Ratchet"] = L["Ratchet"],
						["The Salty Sailor Tavern"] = L["The Salty Sailor Tavern"],
						["Cenarion Hold"] = L["Cenarion Hold"],
--						["Shattrath City"] = L["Shattrath City"],
--						["Area 52"] = L["Area 52"],
--						["Dalaran"] = L["Dalaran"],
--						["Bogpaddle"] = L["Bogpaddle"],
--						["The Vindicaar"] = L["The Vindicaar"],
--						["Krasus' Landing"] = L["Krasus' Landing"],
--						["The Violet Gate"] = L["The Violet Gate"],
--						["Magni's Encampment"] = L["Magni's Encampment"],
--						["Chamber of Heart"] = L["Chamber of Heart"],
--						["Hall of Ancient Paths"] = L["Hall of Ancient Paths"],
--						["Sanctum of the Sages"] = L["Sanctum of the Sages"],
--						["Rustbolt"] = L["Rustbolt"],
--						["Oribos"] = L["Oribos"],
--						["Valdrakken"] = L["Valdrakken"],
--						["The Roasted Ram"] = L["The Roasted Ram"],
--						["Dornogal"] = L["Dornogal"],						
--						["Stonelight Rest"] = L["Stonelight Rest"],
--						["Delver's Headquarters"] = L["Delver's Headquarters"],
					},
				},
				ShowOnDetection = {
					name = L["ShowOnDetection"],
					desc = L["ShowOnDetectionDescription"],
					type = "toggle",
					order = 8,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.ShowOnDetection
					end,
					set = function(info, value)
						VoidMark.db.profile.ShowOnDetection = value
					end,
				},
				HideVoidMark = {
					name = L["HideVoidMark"],
					desc = L["HideVoidMarkDescription"],
					type = "toggle",
					order = 9,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.HideVoidMark
					end,
					set = function(info, value)
						VoidMark.db.profile.HideVoidMark = value
						if VoidMark.db.profile.HideVoidMark and VoidMark:GetNearbyListSize() == 0 then
							VoidMark.MainWindow:Hide()
						end
					end,
				},
--[[				ShowOnlyPvPFlagged = {
					name = L["ShowOnlyPvPFlagged"],
					desc = L["ShowOnlyPvPFlaggedDescription"],
					type = "toggle",
					order = 4,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.ShowOnlyPvPFlagged
					end,
					set = function(info, value)
						VoidMark.db.profile.ShowOnlyPvPFlagged = value
					end,
				},	]]--
				ShowKoSButton = {
					name = L["ShowKoSButton"],
					desc = L["ShowKoSButtonDescription"],
					type = "toggle",
					order = 10,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.ShowKoSButton
					end,
					set = function(info, value)
						VoidMark.db.profile.ShowKoSButton = value
					end,
				},
			},
		},
		DisplayOptions = {
			name = L["DisplayOptions"],
			desc = L["DisplayOptions"],
			type = "group",
			order = 2,
			args = {
				intro = {
					name = L["DisplayOptionsDescription"],
					type = "description",
					order = 1,
					fontSize = "medium",
				},
				ShowNearbyList = {
					name = L["ShowNearbyList"],
					desc = L["ShowNearbyListDescription"],
					type = "toggle",
					order = 2,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.ShowNearbyList
					end,
					set = function(info, value)
						VoidMark.db.profile.ShowNearbyList = value
					end,
				},
				PrioritiseKoS = {
					name = L["PrioritiseKoS"],
					desc = L["PrioritiseKoSDescription"],
					type = "toggle",
					order = 3,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.PrioritiseKoS
					end,
					set = function(info, value)
						VoidMark.db.profile.PrioritiseKoS = value
					end,
				},
				Alpha = {
					name = L["Alpha"],
					desc = L["AlphaDescription"],
					type = "range",
					order = 4,
--					width = "double",
					min = 0, max = 1, step = 0.01,
					isPercent = true,
					get = function()
						return VoidMark.db.profile.MainWindow.Alpha end,
					set = function(info, value)
						VoidMark.db.profile.MainWindow.Alpha = value
						VoidMark:UpdateMainWindow()

					end,
				},
				AlphaBG = {
					name = L["AlphaBG"],
					desc = L["AlphaBGDescription"],
					type = "range",
					order = 5,
--					width = "double",
					min = 0, max = 1, step = 0.01,
					isPercent = true,
					get = function()
						return VoidMark.db.profile.MainWindow.AlphaBG end,
					set = function(info, value)
						VoidMark.db.profile.MainWindow.AlphaBG = value
						VoidMark:UpdateMainWindow()
					end,
				},
				Lock = {
					name = L["LockVoidMark"],
					desc = L["LockVoidMarkDescription"],
					type = "toggle",
					order = 6,
					width = 1.6,
					get = function(info) 
						return VoidMark.db.profile.Locked
					end,
					set = function(info, value)
						VoidMark.db.profile.Locked = value
						VoidMark:LockWindows(value)
						VoidMark:RefreshCurrentList()
					end,
				},
				ClampToScreen = {
					name = L["ClampToScreen"],
					desc = L["ClampToScreenDescription"],
					type = "toggle",
					order = 7,
--					width = "double",
					get = function(info) 
						return VoidMark.db.profile.ClampToScreen
					end,
					set = function(info, value)
						VoidMark.db.profile.ClampToScreen = value
						VoidMark:ClampToScreen(value)
					end,
				},
				InvertVoidMark = {
					name = L["InvertVoidMark"],
					desc = L["InvertVoidMarkDescription"],
					type = "toggle",
					order = 8,
					get = function(info)
						return VoidMark.db.profile.InvertVoidMark
					end,
					set = function(info, value)
						VoidMark.db.profile.InvertVoidMark = value
					end,
				},
				[L["Reload"]] = {
					name = L["Reload"],
					desc = L["ReloadDescription"],
					type = 'execute',
					order = 9,
					width = .6,
					func = function()
						C_UI.Reload()
					end
				},
				ResizeVoidMark = {
					name = L["ResizeVoidMark"],
					desc = L["ResizeVoidMarkDescription"],
					type = "toggle",
					order = 10,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.ResizeVoidMark
					end,
					set = function(info, value)
						VoidMark.db.profile.ResizeVoidMark = value
						if value then VoidMark:RefreshCurrentList() end
					end,
				},
				ResizeVoidMarkLimit = {  
					type = "range",
					order = 11,
					name = L["ResizeVoidMarkLimit"],
					desc = L["ResizeVoidMarkLimitDescription"],
					min = 1, max = 15, step = 1,
					get = function() return VoidMark.db.profile.ResizeVoidMarkLimit end,
					set = function(info, value)
						VoidMark.db.profile.ResizeVoidMarkLimit = value
						if value then 
							VoidMark:ResizeMainWindow()
							VoidMark:RefreshCurrentList() 
						end	
					end,
				},
				DisplayListData = {
					name = L["DisplayListData"],
					type = 'select',
					order = 12,
					values = {
						["1NameLevelClass"] = L["Name"].." / "..L["Level"].." / "..L["Class"],
						["2NameLevelGuild"] = L["Name"].." / "..L["Level"].." / "..L["Guild"],
						["3NameLevelOnly"] = L["Name"].." / "..L["Level"],
						["4NamePvPRank"] = L["Name"].." / "..L["Rank"],
						["5NameGuild"] = L["Name"].." / "..L["Guild"],
						["6NameOnly"] = L["Name"],
					},
					get = function()
						return VoidMark.db.profile.DisplayListData
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayListData = value
						VoidMark:RefreshCurrentList() 
					end,
				},
				SelectFont = {
					type = "select",
					order = 13,
					name = L["SelectFont"],
					desc = L["SelectFontDescription"],
					values = fonts,
					get = function()
						for info, value in next, fonts do
							if value == VoidMark.db.profile.Font then
								return info
							end
						end
					end,
					set = function(_, value)
						VoidMark.db.profile.Font = fonts[value]
						if value then
							VoidMark:UpdateBarTextures()
						end
					end,
				},
				RowHeight = {
					type = "range",
					order = 14,
					name = L["RowHeight"], 
					desc = L["RowHeightDescription"], 
					min = 8, max = 20, step = 1,
					get = function()
						return VoidMark.db.profile.MainWindow.RowHeight
					end,
					set = function(info, value)
						VoidMark.db.profile.MainWindow.RowHeight = value
						if value then
							VoidMark:BarsChanged()
						end
					end,
				},
				BarTexture = {
					type = "select",
					order = 15,
					name = L["Texture"],
					desc = L["TextureDescription"],	
					dialogControl = "LSM30_Statusbar",
					width = "double",
					values = SM:HashTable("statusbar"),
					get = function()
						return VoidMark.db.profile.BarTexture
					end,
					set = function(_, key)
						VoidMark.db.profile.BarTexture = key
						VoidMark:UpdateBarTextures()
					end,
				},
				DisplayTooltipNearVoidMarkWindow = {
					name = L["DisplayTooltipNearVoidMarkWindow"],
					desc = L["DisplayTooltipNearVoidMarkWindowDescription"],
					type = "toggle",
					order = 16,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.DisplayTooltipNearVoidMarkWindow
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayTooltipNearVoidMarkWindow = value
					end,
				},	
				SelectTooltipAnchor = {
					type = "select",
					order = 17,
					name = L["SelectTooltipAnchor"],
					desc = L["SelectTooltipAnchorDescription"],
					values = { 
						["ANCHOR_CURSOR"] = L["ANCHOR_CURSOR"],
						["ANCHOR_TOP"] = L["ANCHOR_TOP"],
						["ANCHOR_BOTTOM"] = L["ANCHOR_BOTTOM"],
						["ANCHOR_LEFT"] = L["ANCHOR_LEFT"],
						["ANCHOR_RIGHT"] = L["ANCHOR_RIGHT"], 
					},
					get = function()
						return VoidMark.db.profile.TooltipAnchor
					end,
					set = function(info, value)
						VoidMark.db.profile.TooltipAnchor = value
					end,
				},
				DisplayWinLossStatistics = {
					name = L["TooltipDisplayWinLoss"],
					desc = L["TooltipDisplayWinLossDescription"],
					type = "toggle",
					order = 18,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.DisplayWinLossStatistics
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayWinLossStatistics = value
					end,
				},
				DisplayKOSReason = {
					name = L["TooltipDisplayKOSReason"],
					desc = L["TooltipDisplayKOSReasonDescription"],
					type = "toggle",
					order = 19,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.DisplayKOSReason
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayKOSReason = value
					end,
				},
				DisplayLastSeen = {
					name = L["TooltipDisplayLastSeen"],
					desc = L["TooltipDisplayLastSeenDescription"],
					type = "toggle",
					order = 20,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.DisplayLastSeen
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayLastSeen = value
					end,
				},
			},
		},
		AlertOptions = {
			name = L["AlertOptions"],
			desc = L["AlertOptions"],
			type = "group",
			order = 3,
			args = {
				intro = {
					name = L["AlertOptionsDescription"],
					type = "description",
					order = 1,
					fontSize = "medium",
				},
				EnableSound = {
					name = L["EnableSound"],
					desc = L["EnableSoundDescription"],
					type = "toggle",
					order = 2,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.EnableSound
					end,
					set = function(info, value)
						VoidMark.db.profile.EnableSound = value
					end,
				},
				SoundChannel = {
					name = L["SoundChannel"],
					type = 'select',
					order = 3,
					values = {
						["Master"] = L["Master"],
						["SFX"] = L["SFX"],
						["Music"] = L["Music"],
						["Ambience"] = L["Ambience"],
					},					
					get = function()
						return VoidMark.db.profile.SoundChannel
					end,
					set = function(info, value)
						VoidMark.db.profile.SoundChannel = value 
					end,
				},
				OnlySoundKoS = {
					name = L["OnlySoundKoS"],
					desc = L["OnlySoundKoSDescription"],
					type = "toggle",
					order = 4,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.OnlySoundKoS
					end,
					set = function(info, value)
						VoidMark.db.profile.OnlySoundKoS = value
					end,
				},
				StopAlertsOnTaxi = {
					name = L["StopAlertsOnTaxi"],
					desc = L["StopAlertsOnTaxiDescription"],
					type = "toggle",
					order = 5,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.StopAlertsOnTaxi
					end,
					set = function(info, value)
						VoidMark.db.profile.StopAlertsOnTaxi = value
					end,
				},
				Announce = {
					name = L["Announce"],
					type = "group",
					order = 6,
					inline = true,
					args = {
						None = {
							name = L["None"],
							desc = L["NoneDescription"],
							type = "toggle",
							order = 1,
							get = function(info)
								return VoidMark.db.profile.Announce == "None"
							end,
							set = function(info, value)
								VoidMark.db.profile.Announce = "None"
							end,
						},
						Self = {
							name = L["Self"],
							desc = L["SelfDescription"],
							type = "toggle",
							order = 2,
							get = function(info)
								return VoidMark.db.profile.Announce == "Self"
							end,
							set = function(info, value)
								VoidMark.db.profile.Announce = "Self"
							end,
						},
						Party = {
							name = L["Party"],
							desc = L["PartyDescription"],
							type = "toggle",
							order = 3,
							get = function(info)
								return VoidMark.db.profile.Announce == "Party"
							end,
							set = function(info, value)
								VoidMark.db.profile.Announce = "Party"
							end,
						},
						Guild = {
							name = L["Guild"],
							desc = L["GuildDescription"],
							type = "toggle",
							order = 4,
							get = function(info)
								return VoidMark.db.profile.Announce == "Guild"
							end,
							set = function(info, value)
								VoidMark.db.profile.Announce = "Guild"
							end,
						},
						Raid = {
							name = L["Raid"],
							desc = L["RaidDescription"],
							type = "toggle",
							order = 5,
							get = function(info)
								return VoidMark.db.profile.Announce == "Raid"
							end,
							set = function(info, value)
								VoidMark.db.profile.Announce = "Raid"
							end,
						},
					},
				},
				OnlyAnnounceKoS = {
					name = L["OnlyAnnounceKoS"],
					desc = L["OnlyAnnounceKoSDescription"],
					type = "toggle",
					order = 7,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.OnlyAnnounceKoS
					end,
					set = function(info, value)
						VoidMark.db.profile.OnlyAnnounceKoS = value
					end,
				},
				DisplayWarnings = {
					name = L["DisplayWarnings"],
					type = 'select',
					order = 8,
					values = {
						["Default"] = L["Default"],
						["ErrorFrame"] = L["ErrorFrame"],
						["Moveable"] = L["Moveable"],
					},
					get = function()
						return VoidMark.db.profile.DisplayWarnings
					end,
					set = function(info, value)
						VoidMark.db.profile.DisplayWarnings = value
						VoidMark:UpdateAlertWindow()
					end,
				},
				WarnOnStealth = {
					name = L["WarnOnStealth"],
					desc = L["WarnOnStealthDescription"],
					type = "toggle",
					order = 9,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.WarnOnStealth
					end,
					set = function(info, value)
						VoidMark.db.profile.WarnOnStealth = value
					end,
				},
				WarnOnKOS = {
					name = L["WarnOnKOS"],
					desc = L["WarnOnKOSDescription"],
					type = "toggle",
					order = 10,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.WarnOnKOS
					end,
					set = function(info, value)
						VoidMark.db.profile.WarnOnKOS = value
					end,
				},
				WarnOnKOSGuild = {
					name = L["WarnOnKOSGuild"],
					desc = L["WarnOnKOSGuildDescription"],
					type = "toggle",
					order = 11,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.WarnOnKOSGuild
					end,
					set = function(info, value)
						VoidMark.db.profile.WarnOnKOSGuild = value
					end,
				},
				WarnOnRace = {
					name = L["WarnOnRace"],
					desc = L["WarnOnRaceDescription"],
					type = "toggle",
					order = 12,
					width = "full",
					get = function(info)
						return VoidMark.db.profile.WarnOnRace
					end,
					set = function(info, value)
						VoidMark.db.profile.WarnOnRace = value
					end,
				},
				SelectWarnRace = {
					type = "select",
					order = 13,
					name = L["SelectWarnRace"],
					desc = L["SelectWarnRaceDescription"],
					get = function()
						return VoidMark.db.profile.SelectWarnRace
					end,
					set = function(info, value)
						VoidMark.db.profile.SelectWarnRace = value
					end,
					values = function()
						local raceOptions = {}
						local races = {
							Alliance = {
								["None"] = L["None"],
								["Human"] = L["Human"],
								["Dwarf"] = L["Dwarf"],
								["Night Elf"] = L["Night Elf"],
								["Gnome"] = L["Gnome"],
--								["Draenei"] = L["Draenei"],
--								["Worgen"] = L["Worgen"],
--								["Pandaren"] = L["Pandaren"],
--								["Lightforged Draenei"] = L["Lightforged Draenei"],
--								["Void Elf"] = L["Void Elf"],
--								["Dark Iron Dwarf"] = L["Dark Iron Dwarf"],
--								["Kul Tiran"] = L["Kul Tiran"],
--								["Mechagnome"] = L["Mechagnome"],
--								["Dracthyr"] = L["Dracthyr"],
--								["Earthen"] = L["Earthen"],
							},
							Horde = {
								["None"] = L["None"],
								["Orc"] = L["Orc"],
								["Tauren"] = L["Tauren"],
								["Troll"] = L["Troll"],
								["Undead"] = L["Undead"],
--								["Blood Elf"] = L["Blood Elf"],
--								["Goblin"] = L["Goblin"],
--								["Pandaren"] = L["Pandaren"],
--								["Highmountain Tauren"] = L["Highmountain Tauren"],
--								["Nightborne"] = L["Nightborne"],
--								["Mag'har Orc"] = L["Mag'har Orc"],
--								["Zandalari Troll"] = L["Zandalari Troll"],
--								["Vulpera"] = L["Vulpera"],
--								["Dracthyr"] = L["Dracthyr"],
--								["Earthen"] = L["Earthen"],
							},
						}
						if VoidMark.EnemyFactionName == "Alliance" then
							raceOptions = races.Alliance
						end	
						if VoidMark.EnemyFactionName == "Horde" then
							raceOptions = races.Horde
						end	
						return raceOptions
					end,
				},
				WarnRaceNote = {
					order = 14,
					type = "description",
					name = L["WarnRaceNote"],
				},
			},
		},
		TrackingOptions = {
			name = "Tracking",
			desc = "VoidMark tracking behavior",
			type = "group",
			order = 5,
			args = {
				intro = {
					name = "|cffb86cffPermanent history|r\nVoidMark never age-purges player records, KOS entries, or win/loss history. Map/minimap tracking and old VoidMark-user data sharing are disabled in this build.",
					type = "description",
					order = 1,
					fontSize = "medium",
				},
				RemoveUndetected = {
					name = "Nearby list timeout",
					desc = "How long an enemy stays in the live Nearby list after activity stops. This only clears the live list; it never deletes the player's saved history.",
					type = "select",
					order = 2,
					values = {
						OneMinute = "1 minute",
						TwoMinutes = "2 minutes",
						FiveMinutes = "5 minutes",
						TenMinutes = "10 minutes",
						FifteenMinutes = "15 minutes",
						Never = "Never",
					},
					get = function()
						return VoidMark.db.profile.RemoveUndetected or "OneMinute"
					end,
					set = function(info, value)
						VoidMark.db.profile.RemoveUndetected = value
						VoidMark:UpdateTimeoutSettings()
					end,
				},
				permanent = {
					name = "Saved enemy history: |cff66ff66PERMANENT|r\nKOS sharing between your own characters: |cff66ff66ON|r\nMap/minimap enemy overlays: |cffff6666OFF|r\nOther VoidMark user data sharing: |cffff6666OFF|r",
					type = "description",
					order = 3,
				},
			},
		},
	},
}

VoidMark.optionsSlash = {
	name = "VoidMark Commands",
	order = -3,
	type = "group",
	args = {
		intro = {
			name = "VoidMark commands. Use /vm or /voidmark.",
			type = "description",
			order = 1,
			cmdHidden = true,
		},
		show = {
			name = L["Show"],
			desc = L["ShowDescription"],
			type = 'execute',
			order = 2,
			func = function()
				VoidMark:EnableVoidMark(true, true)
			end,
			dialogHidden = true
		},
		hide = {
			name = L["Hide"],
			desc = L["HideDescription"],
			type = 'execute',
			order = 3,
			func = function()
				VoidMark:EnableVoidMark(false, true)
			end,
			dialogHidden = true
		},		
		reset = {
			name = L["Reset"],
			desc = "Resets the position of the VoidMark windows.",
			type = 'execute',
			order = 4,
			func = function()
				VoidMark:ResetPositions()
			end,
			dialogHidden = true
		},
		clear = {
			name = L["ClearSlash"],
			desc = L["ClearSlashDescription"],
			type = 'execute',
			order = 5,
			func = function()
				VoidMark:ClearList()
			end,
			dialogHidden = true
		},			
		config = {
			name = L["Config"],
			desc = "Open the Interface AddOns configuration window for VoidMark.",
			type = 'execute',
			order = 6,
			func = function()
				VoidMark:ShowConfig()
			end,
			dialogHidden = true
		},
		kos = {
			name = L["KOS"],
			desc = L["KOSDescription"],
			type = 'input',
			order = 7,
			pattern = ".",	-- Changed so names with special characters can be added
			set = function(info, value)
				if VoidMark_IgnoreList[value] or strmatch(value, "[%s%d]+") then
					DEFAULT_CHAT_FRAME:AddMessage(value .. " - " .. L["InvalidInput"])
				else
					VoidMark:ToggleKOSPlayer(not VoidMarkPerCharDB.KOSData[value], value)
				end	
			end,
			dialogHidden = true
		}, 
		ignore = {
			name = L["Ignore"],
			desc = L["IgnoreDescription"],
			type = 'input',
			order = 8,
			pattern = ".",
			set = function(info, value)
				if VoidMark_IgnoreList[value] or strmatch(value, "[%s%d]+") then
					DEFAULT_CHAT_FRAME:AddMessage(value .. " - " .. L["InvalidInput"])
				else
					VoidMark:ToggleIgnorePlayer(not VoidMarkPerCharDB.IgnoreData[value], value)
				end
			end,
			dialogHidden = true
		},
		stats = {
			name = L["Statistics"],
			desc = L["StatsDescription"],
			type = 'execute',
			order = 9,
			func = function()
				VoidMarkStats:Toggle()
			end,
			dialogHidden = true
		},
		test = {
			name = L["Test"],
			desc = L["TestDescription"],
			type = 'execute',
			order = 10,
			func = function()
				VoidMark:AlertStealthPlayer("Bazzalan")
			end
		},
--[[		sanc = {
			name = L["Sanctuary"],
			desc = L["SanctuaryDescription"],
			type = 'execute',
			order = 11,
			func = function()
				VoidMark.db.profile.EnabledInSanctuaries = not VoidMark.db.profile.EnabledInSanctuaries
				VoidMark:ZoneChangedEvent()
	--			VoidMark:UpdateMainWindow()
	--			VoidMark:EnableVoidMark(false, true)
			end,
			dialogHidden = true
		}, ]]--
	},
}

local Default_Profile = {
	profile = {
		Colors = {
			["Window"] = {
				["Title"] = { r = 1, g = 1, b = 1, a = 1 },
				["Background"]= { r = 24/255, g = 24/255, b = 24/255, a = 1 },
				["Title Text"] = { r = 1, g = 1, b = 1, a = 1 },
			},
			["Other Windows"] = {
				["Title"] = { r = 1, g = 0, b = 0, a = 1 },
				["Background"]= { r = 24/255, g = 24/255, b = 24/255, a = 1 },
				["Title Text"] = { r = 1, g = 1, b = 1, a = 1 },
			},
			["Bar"] = {
				["Bar Text"] = { r = 1, g = 1, b = 1 },
			},
			["Warning"] = {
				["Warning Text"] = { r = 1, g = 1, b = 1 },
			},
			["Tooltip"] = {
				["Title Text"] = { r = 0.8, g = 0.3, b = 0.22 },
				["Details Text"] = { r = 1, g = 1, b = 1 },
				["Location Text"] = { r = 1, g = 0.82, b = 0 },
				["Reason Text"] = { r = 1, g = 0, b = 0 },
			},
			["Alert"] = {
				["Background"]= { r = 0, g = 0, b = 0, a = 0.4 },
				["Icon"] = { r = 1, g = 1, b = 1, a = 0.5 },
				["KOS Border"] = { r = 1, g = 0, b = 0, a = 0.4 },
				["KOS Text"] = { r = 1, g = 0, b = 0 },
				["KOS Guild Border"] = { r = 1, g = 0.82, b = 0, a = 0.4 },
				["KOS Guild Text"] = { r = 1, g = 0.82, b = 0 },
				["Stealth Border"] = { r = 0.6, g = 0.2, b = 1, a = 0.4 },
				["Stealth Text"] = { r = 0.6, g = 0.2, b = 1 },
				["Away Border"] = { r = 0, g = 1, b = 0, a = 0.4 },
				["Away Text"] = { r = 0, g = 1, b = 0 },
				["Location Text"] = { r = 1, g = 0.82, b = 0 },
				["Name Text"] = { r = 1, g = 1, b = 1 },
			},
			["Class"] = {
				["HUNTER"] = { r = 0.67, g = 0.83, b = 0.45, a = 0.6 },
				["WARLOCK"] = { r = 0.53, g = 0.53, b = 0.93, a = 0.6 },
				["PRIEST"] = { r = 1.00, g = 1.00, b = 1.00, a = 0.6 },
				["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, a = 0.6 },
				["MAGE"] = { r = 0.25, g = 0.78, b = 0.92, a = 0.6 },
				["ROGUE"] = { r = 1.00, g = 0.96, b = 0.41, a = 0.6 },
				["DRUID"] = { r = 1.00, g = 0.49, b = 0.04, a = 0.6 },
				["SHAMAN"] = { r = 0.00, g = 0.44, b = 0.87, a = 0.6 },
				["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, a = 0.6 },
--				["DEATHKNIGHT"] = { r = 0.77, g = 0.12, b = 0.23, a = 0.6 },
--				["MONK"] = { r = 0.00, g = 1.00, b = 0.60, a = 0.6 },
--				["DEMONHUNTER"] = { r = 0.64, g = 0.19, b = 0.79, a = 0.6 },
--				["EVOKER"] = { r = 0.20, g = 0.58, b = 0.50, a = 0.6 },
				["PET"] = { r = 0.09, g = 0.61, b = 0.55, a = 0.6 },
				["MOB"] = { r = 0.58, g = 0.24, b = 0.63, a = 0.6 },
				["UNKNOWN"] = { r = 0.1, g = 0.1, b = 0.1, a = 0.6 },
				["HOSTILE"] = { r = 0.7, g = 0.1, b = 0.1, a = 0.6 },
				["UNGROUPED"] = { r = 0.63, g = 0.58, b = 0.24, a = 0.6 },
			},
		},
		MainWindow={
			Alpha=1,
			AlphaBG=1,
			Buttons={
				ClearButton=true,
				LeftButton=true,
				RightButton=true,
			},
			RowHeight=14,
			RowSpacing=2,
			TextHeight=12,
			AutoHide=true,
			BarText={
				RankNum = true,
				PerSec = true,
				Percent = true,
				NumFormat = 1,
			},
			Position={
				x = 4,
				y = 740,
				w = 160,
				h = 34,
			},
		},
		AlertWindow={
			Position={
--				x = 0,
--				y = -140,
				x = 750,
				y = 750,
			},
			NameSize=14,
			LocationSize=10,
		},
		BarTexture="Flat",
		MainWindowVis=true,
		CurrentList=1,
		Locked=false,
		ClampToScreen=true,
		Font="Friz Quadrata TT",
		Scaling=1,
		Enabled=true,
		EnabledInBattlegrounds=true,
		EnabledInSanctuaries=false,
		EnabledInArenas=true,
		EnabledInWintergrasp=true,
		DisableWhenPVPUnflagged=true,
		MinimapDetection=false,
		MinimapDetails=false,
		DisplayOnMap=false,
		SwitchToZone=false,
		MapDisplayLimit="None",
		DisplayTooltipNearVoidMarkWindow=false,
		TooltipAnchor="ANCHOR_CURSOR",
		DisplayWinLossStatistics=true,
		DisplayKOSReason=true,
		DisplayLastSeen=true,
		DisplayListData="1NameLevelClass",
		ShowOnDetection=true,
		HideVoidMark=false,
--		ShowOnlyPvPFlagged=false,
		ShowKoSButton=false,
		InvertVoidMark=false,
		ResizeVoidMark=true,
		ResizeVoidMarkLimit=15,
		SoundChannel="SFX",
		Announce="None",
		OnlyAnnounceKoS=false,
		WarnOnStealth=true,
		WarnOnKOS=true,
		WarnOnKOSGuild=false,
		WarnOnRace=false,
		SelectWarnRace="None",
		DisplayWarnings="Default",
		EnableSound=true,
		OnlySoundKoS=false, 
		StopAlertsOnTaxi=true,
		RemoveUndetected="OneMinute",
		ShowNearbyList=true,
		PrioritiseKoS=true,
		PurgeData="Never",
		PurgeKoS=false,
		PurgeWinLossData=false,
		ShareData=false,
		UseData=false,
		ShareKOSBetweenCharacters=true,
		AppendUnitNameCheck=false,
		AppendUnitKoSCheck=false,
		FilteredZones = {
			["Booty Bay"] = false,
			["Gadgetzan"] = false,
			["Ratchet"] = false,
			["Everlook"] = false,
			["The Salty Sailor Tavern"] = false,
			["Cenarion Hold"] = false,
--			["Shattrath City"] = false,
--			["Area 52"] = false,
--			["Dalaran"] = false,
--			["Bogpaddle"] = false,
--			["The Vindicaar"] = false,
--			["Krasus' Landing"] = false,
--			["The Violet Gate"] = false,
--			["Magni's Encampment"] = false,
--			["Chamber of Heart"] = false,
--			["Hall of Ancient Paths"] = false,
--			["Sanctum of the Sages"] = false,
--			["Rustbolt"] = false,
--			["Oribos"] = false,
--			["Valdrakken"] = false,
--			["The Roasted Ram"] = false,
--			["Dornogal"] = false,
--			["Stonelight Rest"] = false,
--			["Delver's Headquarters"] = false,
		},
	},
}

SM:Register("statusbar", "Flat", [[Interface\Addons\VoidMark\Textures\bar-flat.tga]])

function VoidMark:CheckDatabase()

	--------------------------------------------------
	-- TALIAA VOIDMARK SHARED DATABASE
	-- Shared across characters on the same faction.
	-- Horde and Alliance remain separate.
	--------------------------------------------------

	VoidMarkDB.TaliaaShared = VoidMarkDB.TaliaaShared or {}

	local cluster = (VoidMarkForever and VoidMarkForever.IsForever and "Forever") or "Whitemane"

	VoidMarkDB.TaliaaShared[cluster] =
		VoidMarkDB.TaliaaShared[cluster] or {}

	VoidMarkDB.TaliaaShared[cluster][VoidMark.FactionName] =
		VoidMarkDB.TaliaaShared[cluster][VoidMark.FactionName] or {}

	-- Keep the rest of VoidMark unchanged by redirecting
	-- its normal per-character table to our shared table.
	VoidMarkPerCharDB =
		VoidMarkDB.TaliaaShared[cluster][VoidMark.FactionName]

	VoidMarkPerCharDB.version = VoidMark.DatabaseVersion

	if not VoidMarkPerCharDB.PlayerData then
		VoidMarkPerCharDB.PlayerData = {}
	end

	if not VoidMarkPerCharDB.IgnoreData then
		VoidMarkPerCharDB.IgnoreData = {}
	end

	if not VoidMarkPerCharDB.KOSData then
		VoidMarkPerCharDB.KOSData = {}
	end

	-- Hunt List was removed from VoidMark. Clear any legacy saved entries so
	-- the retired feature does not persist in SavedVariables.
	VoidMarkPerCharDB.HuntData = nil

	-- Remove the retired threat/fight telemetry from existing player records.
	-- Lifetime wins/losses remain in playerData.wins/playerData.loses.
	for _, playerData in pairs(VoidMarkPerCharDB.PlayerData) do
		if type(playerData) == "table" then
			playerData.threatData = nil
		end
	end

	--------------------------------------------------
	-- END TALIAA VOIDMARK SHARED DATABASE
	--------------------------------------------------
	if VoidMarkDB.kosData == nil then VoidMarkDB.kosData = {} end
	if VoidMarkDB.kosData[VoidMark.RealmName] == nil then VoidMarkDB.kosData[VoidMark.RealmName] = {} end
	if VoidMarkDB.kosData[VoidMark.RealmName][VoidMark.FactionName] == nil then VoidMarkDB.kosData[VoidMark.RealmName][VoidMark.FactionName] = {} end
	if VoidMarkDB.kosData[VoidMark.RealmName][VoidMark.FactionName][VoidMark.CharacterName] == nil then VoidMarkDB.kosData[VoidMark.RealmName][VoidMark.FactionName][VoidMark.CharacterName] = {} end
	if VoidMarkDB.removeKOSData == nil then VoidMarkDB.removeKOSData = {} end
	if VoidMarkDB.removeKOSData[VoidMark.RealmName] == nil then VoidMarkDB.removeKOSData[VoidMark.RealmName] = {} end
	if VoidMarkDB.removeKOSData[VoidMark.RealmName][VoidMark.FactionName] == nil then VoidMarkDB.removeKOSData[VoidMark.RealmName][VoidMark.FactionName] = {} end
--[[	if VoidMark.db.profile == nil then VoidMark.db.profile = Default_Profile.profile end
	if VoidMark.db.profile.Colors == nil then VoidMark.db.profile.Colors = Default_Profile.profile.Colors end
	if VoidMark.db.profile.Colors["Window"] == nil then VoidMark.db.profile.Colors["Window"] = Default_Profile.profile.Colors["Window"] end
	if VoidMark.db.profile.Colors["Window"]["Title"] == nil then VoidMark.db.profile.Colors["Window"]["Title"] = Default_Profile.profile.Colors["Window"]["Title"] end
	if VoidMark.db.profile.Colors["Window"]["Background"] == nil then VoidMark.db.profile.Colors["Window"]["Background"] = Default_Profile.profile.Colors["Window"]["Background"] end
	if VoidMark.db.profile.Colors["Window"]["Title Text"] == nil then VoidMark.db.profile.Colors["Window"]["Title Text"] = Default_Profile.profile.Colors["Window"]["Title Text"] end
	if VoidMark.db.profile.Colors["Other Windows"] == nil then VoidMark.db.profile.Colors["Other Windows"] = Default_Profile.profile.Colors["Other Windows"] end
	if VoidMark.db.profile.Colors["Other Windows"]["Title"] == nil then VoidMark.db.profile.Colors["Other Windows"]["Title"] = Default_Profile.profile.Colors["Other Windows"]["Title"] end
	if VoidMark.db.profile.Colors["Other Windows"]["Background"] == nil then VoidMark.db.profile.Colors["Other Windows"]["Background"] = Default_Profile.profile.Colors["Other Windows"]["Background"] end
	if VoidMark.db.profile.Colors["Other Windows"]["Title Text"] == nil then VoidMark.db.profile.Colors["Other Windows"]["Title Text"] = Default_Profile.profile.Colors["Other Windows"]["Title Text"] end
	if VoidMark.db.profile.Colors["Bar"] == nil then VoidMark.db.profile.Colors["Bar"] = Default_Profile.profile.Colors["Bar"] end
	if VoidMark.db.profile.Colors["Bar"]["Bar Text"] == nil then VoidMark.db.profile.Colors["Bar"]["Bar Text"] = Default_Profile.profile.Colors["Bar"]["Bar Text"] end
	if VoidMark.db.profile.Colors["Warning"] == nil then VoidMark.db.profile.Colors["Warning"] = Default_Profile.profile.Colors["Warning"] end
	if VoidMark.db.profile.Colors["Warning"]["Warning Text"] == nil then VoidMark.db.profile.Colors["Warning"]["Warning Text"] = Default_Profile.profile.Colors["Warning"]["Warning Text"] end
	if VoidMark.db.profile.Colors["Tooltip"] == nil then VoidMark.db.profile.Colors["Tooltip"] = Default_Profile.profile.Colors["Tooltip"] end
	if VoidMark.db.profile.Colors["Tooltip"]["Title Text"] == nil then VoidMark.db.profile.Colors["Tooltip"]["Title Text"] = Default_Profile.profile.Colors["Tooltip"]["Title Text"] end
	if VoidMark.db.profile.Colors["Tooltip"]["Details Text"] == nil then VoidMark.db.profile.Colors["Tooltip"]["Details Text"] = Default_Profile.profile.Colors["Tooltip"]["Details Text"] end
	if VoidMark.db.profile.Colors["Tooltip"]["Location Text"] == nil then VoidMark.db.profile.Colors["Tooltip"]["Location Text"] = Default_Profile.profile.Colors["Tooltip"]["Location Text"] end
	if VoidMark.db.profile.Colors["Tooltip"]["Reason Text"] == nil then VoidMark.db.profile.Colors["Tooltip"]["Reason Text"] = Default_Profile.profile.Colors["Tooltip"]["Reason Text"] end
	if VoidMark.db.profile.Colors["Alert"] == nil then VoidMark.db.profile.Colors["Alert"] = Default_Profile.profile.Colors["Alert"] end
	if VoidMark.db.profile.Colors["Alert"]["Background"] == nil then VoidMark.db.profile.Colors["Alert"]["Background"] = Default_Profile.profile.Colors["Alert"]["Background"] end
	if VoidMark.db.profile.Colors["Alert"]["Icon"] == nil then VoidMark.db.profile.Colors["Alert"]["Icon"] = Default_Profile.profile.Colors["Alert"]["Icon"] end
	if VoidMark.db.profile.Colors["Alert"]["KOS Border"] == nil then VoidMark.db.profile.Colors["Alert"]["KOS Border"] = Default_Profile.profile.Colors["Alert"]["KOS Border"] end
	if VoidMark.db.profile.Colors["Alert"]["KOS Text"] == nil then VoidMark.db.profile.Colors["Alert"]["KOS Text"] = Default_Profile.profile.Colors["Alert"]["KOS Text"] end
	if VoidMark.db.profile.Colors["Alert"]["KOS Guild Border"] == nil then VoidMark.db.profile.Colors["Alert"]["KOS Guild Border"] = Default_Profile.profile.Colors["Alert"]["KOS Guild Border"] end
	if VoidMark.db.profile.Colors["Alert"]["KOS Guild Text"] == nil then VoidMark.db.profile.Colors["Alert"]["KOS Guild Text"] = Default_Profile.profile.Colors["Alert"]["KOS Guild Text"] end
	if VoidMark.db.profile.Colors["Alert"]["Stealth Border"] == nil then VoidMark.db.profile.Colors["Alert"]["Stealth Border"] = Default_Profile.profile.Colors["Alert"]["Stealth Border"] end
	if VoidMark.db.profile.Colors["Alert"]["Stealth Text"] == nil then VoidMark.db.profile.Colors["Alert"]["Stealth Text"] = Default_Profile.profile.Colors["Alert"]["Stealth Text"] end
	if VoidMark.db.profile.Colors["Alert"]["Away Border"] == nil then VoidMark.db.profile.Colors["Alert"]["Away Border"] = Default_Profile.profile.Colors["Alert"]["Away Border"] end
	if VoidMark.db.profile.Colors["Alert"]["Away Text"] == nil then VoidMark.db.profile.Colors["Alert"]["Away Text"] = Default_Profile.profile.Colors["Alert"]["Away Text"] end
	if VoidMark.db.profile.Colors["Alert"]["Location Text"] == nil then VoidMark.db.profile.Colors["Alert"]["Location Text"] = Default_Profile.profile.Colors["Alert"]["Location Text"] end
	if VoidMark.db.profile.Colors["Alert"]["Name Text"] == nil then VoidMark.db.profile.Colors["Alert"]["Name Text"] = Default_Profile.profile.Colors["Alert"]["Name Text"] end
	if VoidMark.db.profile.Colors["Class"] == nil then VoidMark.db.profile.Colors["Class"] = Default_Profile.profile.Colors["Class"] end
	if VoidMark.db.profile.Colors["Class"]["HUNTER"] == nil then VoidMark.db.profile.Colors["Class"]["HUNTER"] = Default_Profile.profile.Colors["Class"]["HUNTER"] end
	if VoidMark.db.profile.Colors["Class"]["WARLOCK"] == nil then VoidMark.db.profile.Colors["Class"]["WARLOCK"] = Default_Profile.profile.Colors["Class"]["WARLOCK"] end
	if VoidMark.db.profile.Colors["Class"]["PRIEST"] == nil then VoidMark.db.profile.Colors["Class"]["PRIEST"] = Default_Profile.profile.Colors["Class"]["PRIEST"] end
	if VoidMark.db.profile.Colors["Class"]["PALADIN"] == nil then VoidMark.db.profile.Colors["Class"]["PALADIN"] = Default_Profile.profile.Colors["Class"]["PALADIN"] end
	if VoidMark.db.profile.Colors["Class"]["MAGE"] == nil then VoidMark.db.profile.Colors["Class"]["MAGE"] = Default_Profile.profile.Colors["Class"]["MAGE"] end
	if VoidMark.db.profile.Colors["Class"]["ROGUE"] == nil then VoidMark.db.profile.Colors["Class"]["ROGUE"] = Default_Profile.profile.Colors["Class"]["ROGUE"] end
	if VoidMark.db.profile.Colors["Class"]["DRUID"] == nil then VoidMark.db.profile.Colors["Class"]["DRUID"] = Default_Profile.profile.Colors["Class"]["DRUID"] end
	if VoidMark.db.profile.Colors["Class"]["SHAMAN"] == nil then VoidMark.db.profile.Colors["Class"]["SHAMAN"] = Default_Profile.profile.Colors["Class"]["SHAMAN"] end
	if VoidMark.db.profile.Colors["Class"]["WARRIOR"] == nil then VoidMark.db.profile.Colors["Class"]["WARRIOR"] = Default_Profile.profile.Colors["Class"]["WARRIOR"] end
--	if VoidMark.db.profile.Colors["Class"]["DEATHKNIGHT"] == nil then VoidMark.db.profile.Colors["Class"]["DEATHKNIGHT"] = Default_Profile.profile.Colors["Class"]["DEATHKNIGHT"] end
--	if VoidMark.db.profile.Colors["Class"]["MONK"] == nil then VoidMark.db.profile.Colors["Class"]["MONK"] = Default_Profile.profile.Colors["Class"]["MONK"] end
--	if VoidMark.db.profile.Colors["Class"]["DEMONHUNTER"] == nil then VoidMark.db.profile.Colors["Class"]["DEMONHUNTER"] = Default_Profile.profile.Colors["Class"]["DEMONHUNTER"] end	
	if VoidMark.db.profile.Colors["Class"]["PET"] == nil then VoidMark.db.profile.Colors["Class"]["PET"] = Default_Profile.profile.Colors["Class"]["PET"] end
	if VoidMark.db.profile.Colors["Class"]["MOB"] == nil then VoidMark.db.profile.Colors["Class"]["MOB"] = Default_Profile.profile.Colors["Class"]["MOB"] end
	if VoidMark.db.profile.Colors["Class"]["UNKNOWN"] == nil then VoidMark.db.profile.Colors["Class"]["UNKNOWN"] = Default_Profile.profile.Colors["Class"]["UNKNOWN"] end
	if VoidMark.db.profile.Colors["Class"]["HOSTILE"] == nil then VoidMark.db.profile.Colors["Class"]["HOSTILE"] = Default_Profile.profile.Colors["Class"]["HOSTILE"] end
	if VoidMark.db.profile.Colors["Class"]["UNGROUPED"] == nil then VoidMark.db.profile.Colors["Class"]["UNGROUPED"] = Default_Profile.profile.Colors["Class"]["UNGROUPED"] end
	if VoidMark.db.profile.MainWindow == nil then VoidMark.db.profile.MainWindow = Default_Profile.profile.MainWindow end
	if VoidMark.db.profile.MainWindow.Buttons == nil then VoidMark.db.profile.MainWindow.Buttons = Default_Profile.profile.MainWindow.Buttons end
	if VoidMark.db.profile.MainWindow.Buttons.ClearButton == nil then VoidMark.db.profile.MainWindow.Buttons.ClearButton = Default_Profile.profile.MainWindow.Buttons.ClearButton end
	if VoidMark.db.profile.MainWindow.Buttons.LeftButton == nil then VoidMark.db.profile.MainWindow.Buttons.LeftButton = Default_Profile.profile.MainWindow.Buttons.LeftButton end
	if VoidMark.db.profile.MainWindow.Buttons.RightButton == nil then VoidMark.db.profile.MainWindow.Buttons.RightButton = Default_Profile.profile.MainWindow.Buttons.RightButton end
	if VoidMark.db.profile.MainWindow.RowHeight == nil then VoidMark.db.profile.MainWindow.RowHeight = Default_Profile.profile.MainWindow.RowHeight end
	if VoidMark.db.profile.MainWindow.RowSpacing == nil then VoidMark.db.profile.MainWindow.RowSpacing = Default_Profile.profile.MainWindow.RowSpacing end
	if VoidMark.db.profile.MainWindow.TextHeight == nil then VoidMark.db.profile.MainWindow.TextHeight = Default_Profile.profile.MainWindow.TextHeight end
	if VoidMark.db.profile.MainWindow.AutoHide == nil then VoidMark.db.profile.MainWindow.AutoHide = Default_Profile.profile.MainWindow.AutoHide end
	if VoidMark.db.profile.MainWindow.BarText == nil then VoidMark.db.profile.MainWindow.BarText = Default_Profile.profile.MainWindow.BarText end
	if VoidMark.db.profile.MainWindow.BarText.RankNum == nil then VoidMark.db.profile.MainWindow.BarText.RankNum = Default_Profile.profile.MainWindow.BarText.RankNum end
	if VoidMark.db.profile.MainWindow.BarText.PerSec == nil then VoidMark.db.profile.MainWindow.BarText.PerSec = Default_Profile.profile.MainWindow.BarText.PerSec end
	if VoidMark.db.profile.MainWindow.BarText.Percent == nil then VoidMark.db.profile.MainWindow.BarText.Percent = Default_Profile.profile.MainWindow.BarText.Percent end
	if VoidMark.db.profile.MainWindow.BarText.NumFormat == nil then VoidMark.db.profile.MainWindow.BarText.NumFormat = Default_Profile.profile.MainWindow.BarText.NumFormat end
	if VoidMark.db.profile.MainWindow.Position == nil then VoidMark.db.profile.MainWindow.Position = Default_Profile.profile.MainWindow.Position end
	if VoidMark.db.profile.MainWindow.Position.x == nil then VoidMark.db.profile.MainWindow.Position.x = Default_Profile.profile.MainWindow.Position.x end
	if VoidMark.db.profile.MainWindow.Position.y == nil then VoidMark.db.profile.MainWindow.Position.y = Default_Profile.profile.MainWindow.Position.y end
	if VoidMark.db.profile.MainWindow.Position.w == nil then VoidMark.db.profile.MainWindow.Position.w = Default_Profile.profile.MainWindow.Position.w end
	if VoidMark.db.profile.MainWindow.Position.h == nil then VoidMark.db.profile.MainWindow.Position.h = Default_Profile.profile.MainWindow.Position.h end
	if VoidMark.db.profile.AlertWindowNameSize == nil then VoidMark.db.profile.AlertWindowNameSize = Default_Profile.profile.AlertWindowNameSize end
	if VoidMark.db.profile.AlertWindowLocationSize == nil then VoidMark.db.profile.AlertWindowLocationSize = Default_Profile.profile.AlertWindowLocationSize end
	if VoidMark.db.profile.BarTexture == nil then VoidMark.db.profile.BarTexture = Default_Profile.profile.BarTexture end
	if VoidMark.db.profile.MainWindowVis == nil then VoidMark.db.profile.MainWindowVis = Default_Profile.profile.MainWindowVis end
	if VoidMark.db.profile.CurrentList == nil then VoidMark.db.profile.CurrentList = Default_Profile.profile.CurrentList end
	if VoidMark.db.profile.Locked == nil then VoidMark.db.profile.Locked = Default_Profile.profile.Locked end
	if VoidMark.db.profile.Font == nil then VoidMark.db.profile.Font = Default_Profile.profile.Font end
	if VoidMark.db.profile.Scaling == nil then VoidMark.db.profile.Scaling = Default_Profile.profile.Scaling end
	if VoidMark.db.profile.Enabled == nil then VoidMark.db.profile.Enabled = Default_Profile.profile.Enabled end
	if VoidMark.db.profile.EnabledInBattlegrounds == nil then VoidMark.db.profile.EnabledInBattlegrounds = Default_Profile.profile.EnabledInBattlegrounds end
	if VoidMark.db.profile.EnabledInSanctuaries == nil then VoidMark.db.profile.EnabledInSanctuaries = Default_Profile.profile.EnabledInSanctuaries end
	if VoidMark.db.profile.EnabledInArenas == nil then VoidMark.db.profile.EnabledInArenas = Default_Profile.profile.EnabledInArenas end
	if VoidMark.db.profile.EnabledInWintergrasp == nil then VoidMark.db.profile.EnabledInWintergrasp = Default_Profile.profile.EnabledInWintergrasp end
	if VoidMark.db.profile.DisableWhenPVPUnflagged == nil then VoidMark.db.profile.DisableWhenPVPUnflagged = Default_Profile.profile.DisableWhenPVPUnflagged end
	if VoidMark.db.profile.MinimapDetection == nil then VoidMark.db.profile.MinimapDetection = Default_Profile.profile.MinimapDetection end
	if VoidMark.db.profile.MinimapDetails == nil then VoidMark.db.profile.MinimapDetails = Default_Profile.profile.MinimapDetails end
	if VoidMark.db.profile.DisplayOnMap == nil then VoidMark.db.profile.DisplayOnMap = Default_Profile.profile.DisplayOnMap end
	if VoidMark.db.profile.SwitchToZone == nil then VoidMark.db.profile.SwitchToZone = Default_Profile.profile.SwitchToZone end	
	if VoidMark.db.profile.MapDisplayLimit == nil then VoidMark.db.profile.MapDisplayLimit = Default_Profile.profile.MapDisplayLimit end
	if VoidMark.db.profile.DisplayTooltipNearVoidMarkWindow == nil then VoidMark.db.profile.DisplayTooltipNearVoidMarkWindow = Default_Profile.profile.DisplayTooltipNearVoidMarkWindow end	
	if VoidMark.db.profile.TooltipAnchor == nil then VoidMark.db.profile.TooltipAnchor = Default_Profile.profile.TooltipAnchor end	
	if VoidMark.db.profile.DisplayWinLossStatistics == nil then VoidMark.db.profile.DisplayWinLossStatistics = Default_Profile.profile.DisplayWinLossStatistics end
	if VoidMark.db.profile.DisplayKOSReason == nil then VoidMark.db.profile.DisplayKOSReason = Default_Profile.profile.DisplayKOSReason end
	if VoidMark.db.profile.DisplayLastSeen == nil then VoidMark.db.profile.DisplayLastSeen = Default_Profile.profile.DisplayLastSeen end
	if VoidMark.db.profile.ShowOnDetection == nil then VoidMark.db.profile.ShowOnDetection = Default_Profile.profile.ShowOnDetection end
	if VoidMark.db.profile.HideVoidMark == nil then VoidMark.db.profile.HideVoidMark = Default_Profile.profile.HideVoidMark end
--	if VoidMark.db.profile.ShowOnlyPvPFlagged == nil then VoidMark.db.profile.ShowOnlyPvPFlagged = Default_Profile.profile.ShowOnlyPvPFlagged end	
	if VoidMark.db.profile.ShowKoSButton == nil then VoidMark.db.profile.ShowKoSButton = Default_Profile.profile.ShowKoSButton end	
	if VoidMark.db.profile.InvertVoidMark == nil then VoidMark.db.profile.InvertVoidMark = Default_Profile.profile.InvertVoidMark end
	if VoidMark.db.profile.ResizeVoidMark == nil then VoidMark.db.profile.ResizeVoidMark = Default_Profile.profile.ResizeVoidMark end
	if VoidMark.db.profile.ResizeVoidMarkLimit == nil then VoidMark.db.profile.ResizeVoidMarkLimit = Default_Profile.profile.ResizeVoidMarkLimit end 
	if VoidMark.db.profile.Announce == nil then VoidMark.db.profile.Announce = Default_Profile.profile.Announce end
	if VoidMark.db.profile.OnlyAnnounceKoS == nil then VoidMark.db.profile.OnlyAnnounceKoS = Default_Profile.profile.OnlyAnnounceKoS end
	if VoidMark.db.profile.WarnOnStealth == nil then VoidMark.db.profile.WarnOnStealth = Default_Profile.profile.WarnOnStealth end
	if VoidMark.db.profile.WarnOnKOS == nil then VoidMark.db.profile.WarnOnKOS = Default_Profile.profile.WarnOnKOS end
	if VoidMark.db.profile.WarnOnKOSGuild == nil then VoidMark.db.profile.WarnOnKOSGuild = Default_Profile.profile.WarnOnKOSGuild end
	if VoidMark.db.profile.WarnOnRace == nil then VoidMark.db.profile.WarnOnRace = Default_Profile.profile.WarnOnRace end
	if VoidMark.db.profile.SelectWarnRace == nil then VoidMark.db.profile.SelectWarnRace = Default_Profile.profile.SelectWarnRace end
	if VoidMark.db.profile.DisplayWarningsInErrorsFrame == nil then VoidMark.db.profile.DisplayWarningsInErrorsFrame = Default_Profile.profile.DisplayWarningsInErrorsFrame end
	if VoidMark.db.profile.EnableSound == nil then VoidMark.db.profile.EnableSound = Default_Profile.profile.EnableSound end
	if VoidMark.db.profile.OnlySoundKoS == nil then VoidMark.db.profile.OnlySoundKoS = Default_Profile.profile.OnlySoundKoS end	
	if VoidMark.db.profile.StopAlertsOnTaxi == nil then VoidMark.db.profile.StopAlertsOnTaxi = Default_Profile.profile.StopAlertsOnTaxi end 	
	if VoidMark.db.profile.RemoveUndetected == nil then VoidMark.db.profile.RemoveUndetected = Default_Profile.profile.RemoveUndetected end
	if VoidMark.db.profile.ShowNearbyList == nil then VoidMark.db.profile.ShowNearbyList = Default_Profile.profile.ShowNearbyList end
	if VoidMark.db.profile.PrioritiseKoS == nil then VoidMark.db.profile.PrioritiseKoS = Default_Profile.profile.PrioritiseKoS end
	if VoidMark.db.profile.PurgeData == nil then VoidMark.db.profile.PurgeData = Default_Profile.profile.PurgeData end
	if VoidMark.db.profile.PurgeKoS == nil then VoidMark.db.profile.PurgeKoS = Default_Profile.profile.PurgeKoSData end	
	if VoidMark.db.profile.PurgeWinLossData == nil then VoidMark.db.profile.PurgeWinLossData = Default_Profile.profile.PurgeWinLossData end	
	if VoidMark.db.profile.ShareData == nil then VoidMark.db.profile.ShareData = Default_Profile.profile.ShareData end
	if VoidMark.db.profile.UseData == nil then VoidMark.db.profile.UseData = Default_Profile.profile.UseData end
	if VoidMark.db.profile.ShareKOSBetweenCharacters == nil then VoidMark.db.profile.ShareKOSBetweenCharacters = Default_Profile.profile.ShareKOSBetweenCharacters end
	if VoidMark.db.profile.AppendUnitNameCheck == nil then VoidMark.db.profile.AppendUnitNameCheck = Default_Profile.profile.AppendUnitNameCheck end
	if VoidMark.db.profile.AppendUnitKoSCheck == nil then VoidMark.db.profile.AppendUnitKoSCheck = Default_Profile.profile.AppendUnitKoSCheck end	]]--
end

function VoidMark:ResetProfile()
	VoidMark.db.profile = Default_Profile.profile
--	VoidMark:CheckDatabase()
end

function VoidMark:HandleProfileChanges()
	VoidMark:SanitizeStage1Profile()
	VoidMark:CreateMainWindow()
	VoidMark:RestoreMainWindowPosition(VoidMark.db.profile.MainWindow.Position.x, VoidMark.db.profile.MainWindow.Position.y, VoidMark.db.profile.MainWindow.Position.w, 34)
	VoidMark:ResizeMainWindow()
	VoidMark:UpdateTimeoutSettings()
	VoidMark:LockWindows(VoidMark.db.profile.Locked)
	VoidMark:ClampToScreen(VoidMark.db.profile.ClampToScreen)
end

function VoidMark:RegisterModuleOptions(name, optionTbl, displayName)
	VoidMark.options.args[name] = (type(optionTbl) == "function") and optionTbl() or optionTbl
	local frame, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("VoidMark", displayName, L["VoidMark Option"], name)
	self.optionsFrames[name] = frame
	self.optionsCategoryIDs[name] = categoryID or (frame and frame.name)
end

function VoidMark:SetupOptions()
	self.optionsFrames = {}
	self.optionsCategoryIDs = {}

 	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("VoidMark", VoidMark.options)
	-- VoidMark command aliases.
	LibStub("AceConfig-3.0"):RegisterOptionsTable("VoidMark Commands", VoidMark.optionsSlash, {"voidmark", "vm"})

	local ACD3 = LibStub("AceConfigDialog-3.0")
	local function AddOptionsFrame(key, appName, displayName, parent, group)
		local frame, categoryID = ACD3:AddToBlizOptions(appName, displayName, parent, group)
		self.optionsFrames[key] = frame
		self.optionsCategoryIDs[key] = categoryID or (frame and frame.name)
	end

	AddOptionsFrame("VoidMark", "VoidMark", L["VoidMark Option"], nil, "General")
	AddOptionsFrame("About", "VoidMark", L["About"], L["VoidMark Option"], "About")
	AddOptionsFrame("DisplayOptions", "VoidMark", L["DisplayOptions"], L["VoidMark Option"], "DisplayOptions")
	AddOptionsFrame("AlertOptions", "VoidMark", L["AlertOptions"], L["VoidMark Option"], "AlertOptions")
	AddOptionsFrame("TrackingOptions", "VoidMark", "Tracking", L["VoidMark Option"], "TrackingOptions")

	self:RegisterModuleOptions("Profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db), L["Profiles"])
	VoidMark.options.args.Profiles.order = -2
end

function VoidMark:UpdateTimeoutSettings()
	if not VoidMark.db.profile.RemoveUndetected or VoidMark.db.profile.RemoveUndetected == "OneMinute" then
		VoidMark.ActiveTimeout = 30
		VoidMark.InactiveTimeout = 60
	elseif VoidMark.db.profile.RemoveUndetected == "TwoMinutes" then
		VoidMark.ActiveTimeout = 60
		VoidMark.InactiveTimeout = 120
	elseif VoidMark.db.profile.RemoveUndetected == "FiveMinutes" then
		VoidMark.ActiveTimeout = 150
		VoidMark.InactiveTimeout = 300
	elseif VoidMark.db.profile.RemoveUndetected == "TenMinutes" then
		VoidMark.ActiveTimeout = 300
		VoidMark.InactiveTimeout = 600
	elseif VoidMark.db.profile.RemoveUndetected == "FifteenMinutes" then
		VoidMark.ActiveTimeout = 450
		VoidMark.InactiveTimeout = 900
	elseif VoidMark.db.profile.RemoveUndetected == "Never" then
		VoidMark.ActiveTimeout = 30
		VoidMark.InactiveTimeout = -1
	else
		VoidMark.ActiveTimeout = 150
		VoidMark.InactiveTimeout = 300
	end
end

function VoidMark:ResetMainWindow() -- not used
	VoidMark:EnableVoidMark(true, true)
	VoidMark:CreateMainWindow()
	VoidMark:RestoreMainWindowPosition(Default_Profile.profile.MainWindow.Position.x, Default_Profile.profile.MainWindow.Position.y, Default_Profile.profile.MainWindow.Position.w, 34)
	VoidMark:RefreshCurrentList()
end

function VoidMark:ResetPositions()
	VoidMark:ResetPositionAllWindows()
end

function VoidMark:ShowConfig()
	-- Current Classic Settings expects a registered category ID. Prefer a
	-- numeric child-category ID because passing display-name strings can throw.
	local frames = self.optionsFrames or {}
	local ids = self.optionsCategoryIDs or {}
	local preferred = {"DisplayOptions", "Profiles", "About", "VoidMark"}

	if Settings and Settings.OpenToCategory then
		for _, key in ipairs(preferred) do
			local frame = frames[key]
			local categoryID = ids[key] or (frame and frame.name)
			if type(categoryID) == "number" then
				local ok = pcall(Settings.OpenToCategory, categoryID)
				if ok then return end
			end
		end

		-- Compatibility fallback for clients/AceConfig builds that still use a
		-- non-numeric registered ID. pcall prevents the old settings crash.
		for _, key in ipairs(preferred) do
			local frame = frames[key]
			local categoryID = ids[key] or (frame and frame.name)
			if categoryID ~= nil then
				local ok = pcall(Settings.OpenToCategory, categoryID)
				if ok then return end
			end
		end
	end

	-- Fallback for older clients / AceConfig versions.
	local optionsFrame = frames.DisplayOptions or frames.Profiles or frames.VoidMark
	if InterfaceOptionsFrame_OpenToCategory and optionsFrame then
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
	end
end

function VoidMark:OnEnable(first)
	VoidMark.timeid = VoidMark:ScheduleRepeatingTimer("ManageExpirations", 10, true)
	VoidMark:RegisterEvent("ZONE_CHANGED", "ZoneChangedEvent")
	VoidMark:RegisterEvent("ZONE_CHANGED_INDOORS", "ZoneChangedEvent")
--	VoidMark:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ZoneChangedEvent")
	VoidMark:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ZoneChangedNewAreaEvent")
--	VoidMark:RegisterEvent("PLAYER_ENTERING_WORLD", "ZoneChangedEvent")
	VoidMark:RegisterEvent("PLAYER_ENTERING_WORLD", "PlayerEnteringWorldEvent")
	VoidMark:RegisterEvent("UNIT_FACTION", "ZoneChangedEvent")
	VoidMark:RegisterEvent("PLAYER_TARGET_CHANGED", "PlayerTargetEvent")
	VoidMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "PlayerMouseoverEvent")
	VoidMark:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "CombatLogEvent")
	VoidMark:RegisterEvent("UNIT_PET", "UnitPets")
	VoidMark:RegisterEvent("PLAYER_REGEN_ENABLED", "LeftCombatEvent")
	VoidMark:RegisterEvent("PLAYER_DEAD", "PlayerDeadEvent")
	VoidMark:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", "ChannelNoticeEvent")
	-- VoidMark: only inspect a nameplate while its unit token is valid.
	-- NAME_PLATE_UNIT_REMOVED can arrive after the token is no longer queryable
	-- in Classic Era and can trigger ERR_NAME_PLATE_UNIT_NAME_REQUIRED.
	VoidMark:RegisterEvent("NAME_PLATE_UNIT_ADDED", "NamePlateEvent")
	VoidMark.IsEnabled = true
--	VoidMark:RefreshCurrentList()
end

function VoidMark:OnDisable()
	if not VoidMark.IsEnabled then
		return
	end
	if VoidMark.timeid then
		VoidMark:CancelTimer(VoidMark.timeid)
		VoidMark.timeid = nil
	end
	VoidMark:UnregisterEvent("ZONE_CHANGED")
	VoidMark:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	VoidMark:UnregisterEvent("ZONE_CHANGED_INDOORS")
	VoidMark:UnregisterEvent("PLAYER_ENTERING_WORLD")
	VoidMark:UnregisterEvent("UNIT_FACTION")
	VoidMark:UnregisterEvent("PLAYER_TARGET_CHANGED")
	VoidMark:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	VoidMark:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	VoidMark:UnregisterEvent("PLAYER_REGEN_ENABLED")
	VoidMark:UnregisterEvent("PLAYER_DEAD")
	VoidMark:UnregisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	VoidMark:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
	VoidMark:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
	VoidMark:UnregisterComm(VoidMark.Signature)
	VoidMark.IsEnabled = false
end

function VoidMark:EnableVoidMark(value, changeDisplay, hideEnabledMessage)
	VoidMark.db.profile.Enabled = value
	if value then
		if changeDisplay and not InCombatLockdown() then
			VoidMark.MainWindow:Show()
		end
		VoidMark:OnEnable()
		if not hideEnabledMessage then
			DEFAULT_CHAT_FRAME:AddMessage(L["VoidMarkEnabled"])
		end
	else
		if changeDisplay and not InCombatLockdown() then
			VoidMark.MainWindow:Hide()
		end
		VoidMark:OnDisable()
		DEFAULT_CHAT_FRAME:AddMessage(L["VoidMarkDisabled"])
	end
end

function VoidMark:EnableSound(value)
	VoidMark.db.profile.EnableSound = value
	if value then
		DEFAULT_CHAT_FRAME:AddMessage(L["SoundEnabled"]) 
	else
		DEFAULT_CHAT_FRAME:AddMessage(L["SoundDisabled"])
	end
end

local TALIAA_WHITEMANE_CLUSTER_REALMS = {
	["Whitemane"] = true,
	["Thunderfury"] = true,
	["Fairbanks"] = true,
	["Anathema"] = true,
	["Arcanite Reaper"] = true,
	["Bigglesworth"] = true,
	["Blaumeux"] = true,
	["Kurinnaxx"] = true,
	["Rattlegore"] = true,
	["Smolderweb"] = true,
}

local function TaliaaCanonicalRealm(realm)
	local _, _, _, interfaceVersion = GetBuildInfo()
	if tonumber(interfaceVersion) == 16001 then
		return "Forever"
	end
	if TALIAA_WHITEMANE_CLUSTER_REALMS[realm] then
		return "Whitemane"
	end
	return realm
end

local function TaliaaCopyMissing(dst, src)
	if type(dst) ~= "table" or type(src) ~= "table" then return end
	for key, value in pairs(src) do
		if dst[key] == nil then
			if type(value) == "table" then
				local copy = {}
				TaliaaCopyMissing(copy, value)
				dst[key] = copy
			else
				dst[key] = value
			end
		elseif type(dst[key]) == "table" and type(value) == "table" then
			TaliaaCopyMissing(dst[key], value)
		end
	end
end

function VoidMark:MigrateClusterRealmData()
	if not VoidMarkDB or not VoidMark.ActualRealmName or VoidMark.ActualRealmName == VoidMark.RealmName then return end

	VoidMarkDB.kosData = VoidMarkDB.kosData or {}
	VoidMarkDB.kosData[VoidMark.RealmName] = VoidMarkDB.kosData[VoidMark.RealmName] or {}
	if VoidMarkDB.kosData[VoidMark.ActualRealmName] then
		TaliaaCopyMissing(VoidMarkDB.kosData[VoidMark.RealmName], VoidMarkDB.kosData[VoidMark.ActualRealmName])
	end

	VoidMarkDB.removeKOSData = VoidMarkDB.removeKOSData or {}
	VoidMarkDB.removeKOSData[VoidMark.RealmName] = VoidMarkDB.removeKOSData[VoidMark.RealmName] or {}
	local oldRemoved = VoidMarkDB.removeKOSData[VoidMark.ActualRealmName]
	if oldRemoved then
		for faction, players in pairs(oldRemoved) do
			VoidMarkDB.removeKOSData[VoidMark.RealmName][faction] = VoidMarkDB.removeKOSData[VoidMark.RealmName][faction] or {}
			for player, removedAt in pairs(players) do
				local current = VoidMarkDB.removeKOSData[VoidMark.RealmName][faction][player]
				if current == nil or (tonumber(removedAt) or 0) > (tonumber(current) or 0) then
					VoidMarkDB.removeKOSData[VoidMark.RealmName][faction][player] = removedAt
				end
			end
		end
	end
end

function VoidMark:SanitizeStage1Profile()
	if not VoidMark.db or not VoidMark.db.profile then return end
	local profile = VoidMark.db.profile
	profile.MainWindow = profile.MainWindow or {}
	local mw = profile.MainWindow

	local rowHeight = tonumber(mw.RowHeight)
	if not rowHeight or rowHeight < 8 or rowHeight > 20 then mw.RowHeight = 14 end
	local rowSpacing = tonumber(mw.RowSpacing)
	if not rowSpacing or rowSpacing < 0 or rowSpacing > 10 then mw.RowSpacing = 2 end
	local textHeight = tonumber(mw.TextHeight)
	if not textHeight or textHeight < 8 or textHeight > 20 then mw.TextHeight = 12 end

	mw.Position = mw.Position or {}
	local width = tonumber(mw.Position.w)
	if not width or width < 140 or width > 600 then mw.Position.w = 200 end

	local maxListMode = (VoidMark.ListTypes and #VoidMark.ListTypes) or 4
	if type(profile.CurrentList) ~= "number" or profile.CurrentList < 1 or profile.CurrentList > maxListMode then
		profile.CurrentList = 1
	end

	-- One-time cleanup for legacy per-character profiles. This fixes characters
	-- that inherited oversized rows or opened on an old list mode while leaving
	-- the shared player/KOS/history database untouched.
	VoidMarkDB.TaliaaStage1ProfileFix = VoidMarkDB.TaliaaStage1ProfileFix or {}
	local key = table.concat({ tostring(VoidMark.ActualRealmName or VoidMark.RealmName or "?"), tostring(VoidMark.FactionName or "?"), tostring(VoidMark.CharacterName or "?") }, "|")
	if not VoidMarkDB.TaliaaStage1ProfileFix[key] then
		profile.CurrentList = 1
		profile.Locked = false
		VoidMarkDB.TaliaaStage1ProfileFix[key] = true
	end

	-- VoidMark policy: history is permanent. These legacy VoidMark settings are no
	-- longer user-configurable and cannot be re-enabled by an old profile.
	profile.PurgeData = "Never"
	profile.PurgeKoS = false
	profile.PurgeWinLossData = false
	profile.ShareData = false
	profile.UseData = false
	profile.ShareKOSBetweenCharacters = true
	profile.MinimapDetection = false
	profile.MinimapDetails = false
	profile.DisplayOnMap = false
	profile.SwitchToZone = false
	profile.MapDisplayLimit = "None"
end

function VoidMark:OnInitialize()
	VoidMark.ActualRealmName = GetRealmName()
	VoidMark.RealmName = TaliaaCanonicalRealm(VoidMark.ActualRealmName)
    VoidMark.FactionName = select(1, UnitFactionGroup("player"))
	if VoidMark.FactionName == "Alliance" then
		VoidMark.EnemyFactionName = "Horde"
	elseif VoidMark.FactionName == "Horde" then
		VoidMark.EnemyFactionName = "Alliance"
	else
		VoidMark.EnemyFactionName = "None"
	end
	VoidMark.CharacterName = UnitName("player")

	VoidMark.ValidClasses = {
		["DRUID"] = true,
		["HUNTER"] = true,
		["MAGE"] = true,
		["PALADIN"] = true,
		["PRIEST"] = true,
		["ROGUE"] = true,
		["SHAMAN"] = true,
		["WARLOCK"] = true,
		["WARRIOR"] = true,
--		["DEATHKNIGHT"] = true,
--		["MONK"] = true,
--		["DEMONHUNTER"] = true,
--		["EVOKER"] = true,
	}

	VoidMark.ValidRaces = {
		["Human"] = true,
		["Orc"] = true,
		["Dwarf"] = true,
		["Tauren"] = true,
		["Troll"] = true,
		["NightElf"] = true,
		["Scourge"] = true,
		["Gnome"] = true,
--		["BloodElf"] = true,
--		["Draenei"] = true,
--		["Goblin"] = true,
--		["Worgen"] = true,
--		["Pandaren"] = true,
--		["HighmountainTauren"] = true,
--		["LightforgedDraenei"] = true,
--		["Nightborne"] = true,
--		["VoidElf"] = true,
--		["DarkIronDwarf"] = true,
--		["MagharOrc"] = true,
--		["KulTiran"] = true,
--		["ZandalariTroll"] = true,
--		["Mechagnome"] = true,
--		["Vulpera"] = true,
--		["Dracthyr"] = true,
--		["Earthen"] = true,
	}

	-- One-time database handoff from pre-VoidMark beta builds. The old global
	-- name is assembled at runtime so the retired branding is not carried in
	-- the source or TOC. Once saved, only VoidMarkDB is persisted.
	if VoidMarkDB == nil then
		local retiredDBKey = "S" .. "pyDB"
		local retiredDB = rawget(_G, retiredDBKey)
		if type(retiredDB) == "table" then
			VoidMarkDB = retiredDB
			rawset(_G, retiredDBKey, nil)
		end
	end

	local acedb = LibStub:GetLibrary("AceDB-3.0")

	VoidMark.db = acedb:New("VoidMarkDB", Default_Profile)
	VoidMark:MigrateClusterRealmData()
	VoidMark:SanitizeStage1Profile()
	VoidMark:CheckDatabase()

--	self.db.RegisterCallback(self, "OnNewProfile", "ResetProfile")
	self.db.RegisterCallback(self, "OnNewProfile", "HandleProfileChanges")
--	self.db.RegisterCallback(self, "OnProfileReset", "ResetProfile")
	self.db.RegisterCallback(self, "OnProfileReset", "HandleProfileChanges")
	self.db.RegisterCallback(self, "OnProfileChanged", "HandleProfileChanges")
	self.db.RegisterCallback(self, "OnProfileCopied", "HandleProfileChanges")
	self:SetupOptions()

	VoidMarkTempTooltip = CreateFrame("GameTooltip", "VoidMarkTempTooltip", nil, "GameTooltipTemplate")
	VoidMarkTempTooltip:SetOwner(UIParent, "ANCHOR_NONE")

	VoidMark:RegenerateKOSGuildList()
	if VoidMark.db.profile.ShareKOSBetweenCharacters then
		VoidMark:RemoveLocalKOSPlayers()
		VoidMark:RegenerateKOSCentralList()
		VoidMark:RegenerateKOSListFromCentral()
	end
	VoidMark:PurgeUndetectedData()
	VoidMark:CreateMainWindow()
	VoidMark:CreateKoSButton()
	VoidMark:UpdateTimeoutSettings()

	SM.RegisterCallback(VoidMark, "LibSharedMedia_Registered", "UpdateBarTextures")
	SM.RegisterCallback(VoidMark, "LibSharedMedia_SetGlobal", "UpdateBarTextures")
	if VoidMark.db.profile.BarTexture then
		VoidMark:SetBarTextures(VoidMark.db.profile.BarTexture)
	end

	VoidMark:LockWindows(VoidMark.db.profile.Locked)
	VoidMark:ClampToScreen(VoidMark.db.profile.ClampToScreen)	
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", VoidMark.FilterNotInParty)
	VoidMark.WoWBuildInfo = select(4, GetBuildInfo())
	if VoidMark.WoWBuildInfo > 20000 then
		DEFAULT_CHAT_FRAME:AddMessage(L["VersionCheck"])
	end
end

function VoidMark:ChannelNoticeEvent(_, chStatus, _, _, Channel)
	if chStatus ~= "SUSPENDED" then
		VoidMark.ChnlTime = time()
		local channel, zone = string.match(Channel, "(.+) %- (.+)")
--		local subZone = GetSubZoneText()
		local InFilteredZone = VoidMark:InFilteredZone(zone)
		if InFilteredZone then
			VoidMark.EnabledInZone = false
		end
	end
end

function VoidMark:PlayerEnteringWorldEvent()
	VoidMark.EnabledInZone = false
	local now = time()
	if VoidMark.ChnlTime > (now - 6) then
		self:ScheduleTimer("PlayerEnteringWorldEvent",6)
		return	
	else 
		VoidMark:ZoneChanged()
	end
end

function VoidMark:ZoneChangedEvent()
	local now = time()
	if VoidMark.ChnlTime > (now - 6) then
		self:ScheduleTimer("ZoneChangedEvent",6)
		return
	else 
		VoidMark:ZoneChanged()
	end
end

function VoidMark:ZoneChangedNewAreaEvent()
	local now = time()
	if VoidMark.ChnlTime > (now - 6) then
		self:ScheduleTimer("ZoneChangedNewAreaEvent",6)
		return
	else 
		VoidMark:ZoneChanged()
	end
end

function VoidMark:ZoneChanged()
	VoidMark.InInstance = false
	local pvpType
	if C_PvP and C_PvP.GetZonePVPInfo then
		pvpType = C_PvP.GetZonePVPInfo()
	elseif GetZonePVPInfo then
		pvpType = GetZonePVPInfo()
	end
 	local zone = GetZoneText()
	local subZone = GetSubZoneText()
	local InFilteredZone = VoidMark:InFilteredZone(zone, subZone)
	if pvpType == "sanctuary" and not VoidMark.db.profile.EnabledInSanctuaries then
		VoidMark.EnabledInZone = false
	else
		VoidMark.EnabledInZone = true
		if zone == "" or InFilteredZone then
			VoidMark.EnabledInZone = false
		else
			VoidMark.EnabledInZone = true
			local inInstance, instanceType = IsInInstance()
			if inInstance then
				VoidMark.InInstance = true
				if instanceType == "party" or instanceType == "raid" or (not VoidMark.db.profile.EnabledInBattlegrounds and instanceType == "pvp") or (not VoidMark.db.profile.EnabledInArenas and instanceType == "arena") then
					VoidMark.EnabledInZone = false
				end
			elseif pvpType == "combat" then
				if not VoidMark.db.profile.EnabledInWintergrasp then
					VoidMark.EnabledInZone = false
				end
--			elseif (pvpType == "friendly" or pvpType == nil) then
			elseif UnitIsPVP("player") == false and VoidMark.db.profile.DisableWhenPVPUnflagged then
				VoidMark.EnabledInZone = false
--				end
			end
		end
	end

	if VoidMark.EnabledInZone then
		if not VoidMark.db.profile.HideVoidMark then
			if not InCombatLockdown() then VoidMark.MainWindow:Show() end
			VoidMark:RefreshCurrentList()
		end
	else
		if not InCombatLockdown() then VoidMark.MainWindow:Hide() end
	end
	VoidMark:UpdateMainWindow()
end

function VoidMark:InFilteredZone(zone, subzone)
	local InFilteredZone = false
	for filteredZone, value in pairs(VoidMark.db.profile.FilteredZones) do
		if zone == filteredZone and value then
			InFilteredZone = true
		elseif subzone == filteredZone and value then
			InFilteredZone = true
--			break
		end
	end
	return InFilteredZone
end

function VoidMark:PlayerTargetEvent()
	local name = GetUnitName("target", true)
	if name and UnitIsPlayer("target") and not VoidMarkPerCharDB.IgnoreData[name] then
		local playerData = VoidMarkPerCharDB.PlayerData[name]
		if UnitIsEnemy("player", "target") then
			name = string.gsub(name, " %- ", "-")

			local learnt = true
			if playerData and playerData.isGuess == false then learnt = false end

			local x, class = UnitClass("target")
			local race = select(1,UnitRace("target"))
			local level = tonumber(UnitLevel("target"))
			local guild = GetGuildInfo("target")
			local faction = select(1,UnitFactionGroup("target"))
			local guess = false
			if level == VoidMark.Skull then
				if playerData and playerData.level then
					if playerData.level > (UnitLevel("player") + 10) and playerData.level < VoidMark.MaximumPlayerLevel then	
						guess = true
						level = nil
					elseif UnitLevel("player") < VoidMark.MaximumPlayerLevel - 9 then
						guess = true
						level = UnitLevel("player") + 10
					end	
				else
					guess = true
					level = UnitLevel("player") + 10
				end
--			else
--				guess = true
--				level = nil
			end
			local rankName, rank = GetPVPRankInfo(UnitPVPRank("target"))
			if ( not rank ) then
				rank = nil
			end
			
			VoidMark:UpdatePlayerData(name, class, level, race, guild, faction, true, guess, rank)
			if VoidMark.EnabledInZone then
				VoidMark:AddDetected(name, time(), learnt)
			end
		elseif playerData then
			VoidMark:RemovePlayerData(name)
		end
	end
end

function VoidMark:PlayerMouseoverEvent()
	local name = GetUnitName("mouseover", true)
	if name and UnitIsPlayer("mouseover") and not VoidMarkPerCharDB.IgnoreData[name] then
		local playerData = VoidMarkPerCharDB.PlayerData[name]
		if UnitIsEnemy("player", "mouseover") then
			name = string.gsub(name, " %- ", "-")

			local learnt = true
			if playerData and playerData.isGuess == false then learnt = false end

			local x, class = UnitClass("mouseover")
			local race = select(1,UnitRace("mouseover"))
			local level = tonumber(UnitLevel("mouseover"))
			local guild = GetGuildInfo("mouseover")
			local faction = select(1,UnitFactionGroup("mouseover"))
			local guess = false
			if level == VoidMark.Skull then
				if playerData and playerData.level then
					if playerData.level > (UnitLevel("player") + 10) and playerData.level < VoidMark.MaximumPlayerLevel then	
						guess = true
						level = nil
					elseif UnitLevel("player") < VoidMark.MaximumPlayerLevel - 9 then
						guess = true
						level = UnitLevel("player") + 10
					end	
				else
					guess = true
					level = UnitLevel("player") + 10
				end
--			else
--				guess = true
--				level = nil
			end
			local rankName, rank = GetPVPRankInfo(UnitPVPRank("mouseover"))
			if ( not rank ) then
				rank = nil
			end

			VoidMark:UpdatePlayerData(name, class, level, race, guild, faction, true, guess, rank)
			if VoidMark.EnabledInZone then
				VoidMark:AddDetected(name, time(), learnt)
			end
		elseif playerData then 
			VoidMark:RemovePlayerData(name)
		end
	end
end

function VoidMark:NamePlateEvent(event, unit)
	-- Only NAME_PLATE_UNIT_ADDED is registered now, but keep this guard in
	-- place so an invalid/expired nameplate token can never be queried.
	if event ~= "NAME_PLATE_UNIT_ADDED" then return end
	if type(unit) ~= "string" or unit == "" or not UnitExists(unit) then return end

	local name = GetUnitName(unit, true)
	if name and name ~= "" and UnitIsPlayer(unit) and not VoidMarkPerCharDB.IgnoreData[name] then
		local playerData = VoidMarkPerCharDB.PlayerData[name]
		if UnitIsEnemy("player", unit) then
			name = string.gsub(name, " %- ", "-")

			local learnt = true
			if playerData and playerData.isGuess == false then learnt = false end

			local x, class = UnitClass(unit)
			local race = select(1,UnitRace(unit))
			local level = tonumber(UnitLevel(unit))
			local guild = GetGuildInfo(unit)
			local faction = select(1,UnitFactionGroup(unit))
			local guess = false
			if level == VoidMark.Skull then
				if playerData and playerData.level then
					if playerData.level > (UnitLevel("player") + 10) and playerData.level < VoidMark.MaximumPlayerLevel then	
						guess = true
						level = nil
					elseif UnitLevel("player") < VoidMark.MaximumPlayerLevel - 9 then
						guess = true
						level = UnitLevel("player") + 10
					end	
				else
					guess = true
					level = UnitLevel("player") + 10
				end
--			else
--				guess = true
--				level = nil
			end
			local rankName, rank = GetPVPRankInfo(UnitPVPRank(unit))
			if ( not rank ) then
				rank = nil
			end

			VoidMark:UpdatePlayerData(name, class, level, race, guild, faction, true, guess, rank)
			if VoidMark.EnabledInZone then
				VoidMark:AddDetected(name, time(), learnt)
			end
		elseif playerData then 
			VoidMark:RemovePlayerData(name)
		end
	end
end


--------------------------------------------------
-- VOIDMARK PVP ENGAGEMENT TRACKING
-- Lightweight recent-damage timestamps used only for kill/death attribution.
-- No threat score, confidence, fight telemetry, or damage totals are stored.
--------------------------------------------------

VoidMark.GankRecentDamage = VoidMark.GankRecentDamage or {}
VoidMark.RecentEnemyDamage = VoidMark.RecentEnemyDamage or {}

local VOIDMARK_DEATH_CREDIT_WINDOW = 10
local VOIDMARK_GANK_CREDIT_WINDOW = 30
local VOIDMARK_RECENT_COMBAT_RETENTION = 60
local VoidMarkLastPvPPrune = 0

local function VoidMarkIsHostilePlayer(flags, guid)
	if not flags or not guid then
		return false
	end
	if strsub(guid, 1, 6) ~= "Player" then
		return false
	end
	return bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE
end

local function VoidMarkDamageAmount(event, arg12, arg13, arg14, arg15)
	if event == "SWING_DAMAGE" then
		return tonumber(arg12) or 0
	elseif event == "RANGE_DAMAGE"
		or event == "SPELL_DAMAGE"
		or event == "SPELL_PERIODIC_DAMAGE"
	then
		return tonumber(arg15) or 0
	end
	return 0
end

local function VoidMarkPruneRecentPvP(now)
	if (now - VoidMarkLastPvPPrune) < 10 then
		return
	end
	VoidMarkLastPvPPrune = now

	for player, stamp in pairs(VoidMark.GankRecentDamage) do
		if (now - (tonumber(stamp) or 0)) > VOIDMARK_RECENT_COMBAT_RETENTION then
			VoidMark.GankRecentDamage[player] = nil
		end
	end
	for player, stamp in pairs(VoidMark.RecentEnemyDamage) do
		if (now - (tonumber(stamp) or 0)) > VOIDMARK_RECENT_COMBAT_RETENTION then
			VoidMark.RecentEnemyDamage[player] = nil
		end
	end
end

local function VoidMarkTrackPvPDamage(event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, arg12, arg13, arg14, arg15)
	local amount = VoidMarkDamageAmount(event, arg12, arg13, arg14, arg15)
	if amount <= 0 then
		return
	end

	local playerGUID = UnitGUID("player")
	local now = GetTime()
	VoidMarkPruneRecentPvP(now)

	-- We damaged a hostile player: retain a short assist-credit window.
	if srcGUID == playerGUID
		and dstName
		and VoidMarkIsHostilePlayer(dstFlags, dstGUID)
	then
		VoidMark.GankRecentDamage[dstName] = now
		return
	end

	-- A hostile player damaged us: retain only the most recent hit time so a
	-- PLAYER_DEAD event can assign the lifetime loss to the likely killer.
	if dstGUID == playerGUID
		and srcName
		and VoidMarkIsHostilePlayer(srcFlags, srcGUID)
	then
		VoidMark.RecentEnemyDamage[srcName] = now
	end
end

function VoidMark:CombatLogEvent(info, timestamp, event, hideCaster, srcGUID, srcName, srcFlags, sourceRaidFlags, dstGUID, dstName, dstFlags, destRaidFlags, ...)
timestamp, event, hideCaster, srcGUID, srcName, srcFlags, sourceRaidFlags, dstGUID, dstName, dstFlags, destRaidFlags, arg12, arg13, arg14, arg15, arg16 = CombatLogGetCurrentEventInfo()
	if VoidMark.EnabledInZone then
		
		--PetKill code start
		combatEvent = {
			["SWING_DAMAGE"] = true,
			["RANGE_DAMAGE"] = true,
			["SPELL_DAMAGE"] = true,
			["SPELL_PERIODIC_DAMAGE"] = true,
		}	
		local spellID, spellName, spellSchool, amount, overkill 
		local petName = UnitName("pet"); 
		local _, overkill 	
		overkill = 0;		--PetKill code end
	
		-- analyse the source unit
		if bit.band(srcFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE and srcGUID and srcName and not VoidMarkPerCharDB.IgnoreData[srcName] then
			local srcType = strsub(srcGUID, 1,6)
			if srcType == "Player" then
				local _, class, race, raceFile, _, name = GetPlayerInfoByGUID(srcGUID)
				if not VoidMark.ValidClasses[class] then
					class = nil
				end	
				if not VoidMark.ValidRaces[raceFile] then
					race = nil
				end
				local learnt = false
				local detected = true
				local playerData = VoidMarkPerCharDB.PlayerData[srcName]
				if not playerData or playerData.isGuess then
					learnt, playerData = VoidMark:ParseUnitAbility(true, event, srcName, class, race, arg12, arg13)
				end
				if not learnt then
					detected = VoidMark:UpdatePlayerData(srcName, class, nil, race, nil, nil, true, nil, nil)
				end

				if detected then
					VoidMark:AddDetected(srcName, timestamp, learnt)
					if event == "SPELL_AURA_APPLIED" and (arg13 == L["Stealth"]) then
						VoidMark:PromoteStealthPlayer(srcName, timestamp, "Stealth")
						VoidMark:AlertStealthPlayer(srcName)
					end	
					if event == "SPELL_AURA_APPLIED" and (arg13 == L["Prowl"]) then
						VoidMark:PromoteStealthPlayer(srcName, timestamp, "Prowl")
						VoidMark:AlertProwlPlayer(srcName)
					end
				end
			end

			if dstGUID == UnitGUID("player") then
				VoidMark.LastAttack = srcName
				VoidMark.LastAttackTime = GetTime()
			end
		end

		-- analyse the destination unit
		if bit.band(dstFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == COMBATLOG_OBJECT_REACTION_HOSTILE and dstGUID and dstName and not VoidMarkPerCharDB.IgnoreData[dstName] then
			local dstType = strsub(dstGUID, 1,6)
			if dstType == "Player" then
				local _, class, race, raceFile, _, name = GetPlayerInfoByGUID(dstGUID)
				if not VoidMark.ValidClasses[class] then
					class = nil
				end	
				if not VoidMark.ValidRaces[raceFile] then
					race = nil
				end				
				local learnt = false
				local detected = true
				local playerData = VoidMarkPerCharDB.PlayerData[dstName]
				if not playerData or playerData.isGuess then
					learnt, playerData = VoidMark:ParseUnitAbility(false, event, dstName, class, race, arg12, arg13)
				end
				if not learnt then
					detected = VoidMark:UpdatePlayerData(dstName, class, nil, race, nil, nil, true, nil, nil)
				end
				if detected then
					VoidMark:AddDetected(dstName, timestamp, learnt)
				end
			end
		end

		-- Track only the recent PvP timestamps needed for kill/death attribution.
		if combatEvent[event] then
			VoidMarkTrackPvPDamage(event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, arg12, arg13, arg14, arg15)
		end

		-- Gank Tracker assist credit: count a hostile player death when we
		-- damaged that player recently, even if somebody else got the killing blow.
		if event == "UNIT_DIED" and dstName and dstGUID then
			local isPlayerVictim = strsub(dstGUID, 1, 6) == "Player"
			local playerData = VoidMarkPerCharDB
				and VoidMarkPerCharDB.PlayerData
				and VoidMarkPerCharDB.PlayerData[dstName]
			local isEnemyVictim = playerData and playerData.isEnemy

			local recentDamage = VoidMark.GankRecentDamage[dstName]
			local recentlyEngaged = recentDamage
				and (GetTime() - recentDamage) <= VOIDMARK_GANK_CREDIT_WINDOW

			if isPlayerVictim and isEnemyVictim and recentlyEngaged then
				if TaliaaGankTracker and TaliaaGankTracker.RecordKill then
					TaliaaGankTracker:RecordKill(dstName, dstGUID)
				end
				VoidMark.GankRecentDamage[dstName] = nil
			end
		end
		-- update win stats / Gank Tracker
		if event == "PARTY_KILL" then
			-- PARTY_KILL fires when YOU OR A GROUP MEMBER gets the killing blow.
			-- The tracker should count the group gank, while lifetime W/L stays personal.
			local isPlayerVictim = dstGUID and strsub(dstGUID, 1, 6) == "Player"

			local playerData = dstName and VoidMarkPerCharDB
				and VoidMarkPerCharDB.PlayerData
				and VoidMarkPerCharDB.PlayerData[dstName]

			-- Use either VoidMark's known-enemy flag or combat-log hostility.
			local hostileByDB = playerData and playerData.isEnemy
			local hostileByFlags = dstFlags
				and bit.band(dstFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0
			local isEnemyVictim = hostileByDB or hostileByFlags

			-- Accept kills credited to us, our pet/guardian, party, or raid.
			local sourceIsGroup = srcFlags and (
				bit.band(srcFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0
				or bit.band(srcFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY) > 0
				or bit.band(srcFlags, COMBATLOG_OBJECT_AFFILIATION_RAID) > 0
			)

			local sourceIsPlayer = srcGUID == UnitGUID("player")

			if dstName and isPlayerVictim and isEnemyVictim and sourceIsGroup then
				if TaliaaGankTracker and TaliaaGankTracker.RecordKill then
					TaliaaGankTracker:RecordKill(dstName, dstGUID)
				end
				VoidMark.GankRecentDamage[dstName] = nil

				-- Lifetime W/L remains personal: increment the win only when
				-- this character got the killing blow.
				if sourceIsPlayer and playerData then
					playerData.wins = (tonumber(playerData.wins) or 0) + 1
				end
			end
		end

		-- adds pet kills to the win stats
		if combatEvent[event] then
			if event == "SWING_DAMAGE" then
				if arg13 == nil then
					overkill = 0
				else
					overkill = arg13
				end
			else
				if arg16 == nil then
					overkill = 0
				else
					overkill = arg16
				end
			end
			if (overkill > 1) and dstName then
				if VoidMark.PetGUID[srcGUID] then
					local playerData = VoidMarkPerCharDB.PlayerData[dstName]
					if playerData then
						playerData.wins = (tonumber(playerData.wins) or 0) + 1
--							PlaySoundFile("Interface\\AddOns\\VoidMark\\Sounds\\neck-snap.mp3", VoidMark.db.profile.SoundChannel)
--							DEFAULT_CHAT_FRAME:AddMessage("Your pet/guardian killed " .. dstName);
					end
				end
			end
		end
		if event == "SPELL_SUMMON" and srcName == VoidMark.CharacterName then
			local petGUID = dstGUID
			VoidMark.PetGUID[petGUID] = time()
		end
		if event == "ENVIRONMENTAL_DAMAGE" and dstGUID == UnitGUID("player") then
--			local environmentalType = arg12
--			local amount = arg13
			VoidMark.LastAttack = nil		
--			print(timestamp, "Ouch ", environmentalType, amount, " hurts!")
		end		
	end
end

function VoidMark:LeftCombatEvent()
	VoidMark.LastAttack = nil
	VoidMark:RefreshCurrentList()
	if VoidMark.ClearCombatSightings then
		VoidMark:ClearCombatSightings()
	end
end

function VoidMark:PlayerDeadEvent()
	-- Assign the lifetime loss to the hostile player who damaged us most
	-- recently inside the short death-credit window.
	local now = GetTime()
	local killer = nil
	local newestHit = 0

	for player, hitTime in pairs(VoidMark.RecentEnemyDamage or {}) do
		local stamp = tonumber(hitTime) or 0
		local age = now - stamp
		if age <= VOIDMARK_DEATH_CREDIT_WINDOW and stamp > newestHit then
			newestHit = stamp
			killer = player
		end
	end

	if killer then
		local playerData = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[killer]
		if playerData then
			playerData.loses = (tonumber(playerData.loses) or 0) + 1
		end
	end

	-- A death ends the attribution window; do not let stale hits leak into the
	-- next death.
	for player in pairs(VoidMark.RecentEnemyDamage or {}) do
		VoidMark.RecentEnemyDamage[player] = nil
	end
end

function VoidMark:UnitPets(event, unit)
	local petUnit
	if unit == "player" then
		petUnit = "pet"
	end
	if petUnit and UnitExists(petUnit) then
		local guid = UnitGUID(unit)
		local petGUID = UnitGUID(petUnit)
		VoidMark.PetGUID[petGUID] = time()
		local petCount = 0
		for k, v in pairs(VoidMark.PetGUID) do
			petCount = petCount + 1
			if petCount > 50 then
				if (time() - 9000) > v then
					VoidMark.PetGUID[k] = nil
				end	
			end
		end	
	end
end

function VoidMark:CommReceived(prefix, message, distribution, source)
	-- Removed: VoidMark no longer imports encounter data from other VoidMark users.
	return
end

function VoidMark:VersionCheck(version1, version2)
	local major1, minor1, update1 = strsplit(".", version1)
	local major2, minor2, update2 = strsplit(".", version2)
	major1, minor1, update1 = tonumber(major1), tonumber(minor1), tonumber(update1)
	major2, minor2, update2 = tonumber(major2), tonumber(minor2), tonumber(update2)
	if major1 < major2 then
		return true
	elseif ((major1 == major2) and (minor1 < minor2)) then
		return true
	elseif ((major1 == major2) and (minor1 == minor2) and (update1 < update2)) then
		return true
	else	
		return false
	end
end

function VoidMark:TrackHumanoids()
	-- Removed: legacy minimap tooltip scanning is disabled.
	return
end

function VoidMark:FilterNotInParty(frame, event, message)
	if (event == ERR_NOT_IN_GROUP or event == ERR_NOT_IN_RAID) then
		return true
	end
	return false
end

function VoidMark:ShowMapNote(player)
	-- Removed: VoidMark does not create world-map/minimap enemy pins.
	return
end

function VoidMark:GetPlayerLocation(playerData)
	local location = playerData.zone
	local mapX = playerData.mapX
	local mapY = playerData.mapY
	if location and playerData.subZone and playerData.subZone ~= "" and playerData.subZone ~= location then
		location = playerData.subZone..", "..location
	end
	if mapX and mapX ~= 0 and mapY and mapY ~= 0 then
		location = location.." ("..math.floor(tonumber(mapX) * 100)..","..math.floor(tonumber(mapY) * 100)..")"
	end
	return location
end

function VoidMark:HideVoidMarkCombatCheck()
	if InCombatLockdown() then
		-- MainWindow did not Hide while in combat, try again in 10 seconds.
		self:ScheduleTimer("HideVoidMarkCombatCheck",10)
		return
	else
		VoidMark.MainWindow:Hide()
	end
end

function VoidMark:FormatTime(timestamp)
    if timestamp == 0 then return "Long " end

    local age = time() - timestamp

    local days
    if age >= 86400 then
        days = math.modf(age / 86400)
        age = age - (days * 86400)
    end

    local hours
    if age >= 3600 then
        hours = math.modf(age / 3600)
        age = age - (hours * 3600)
    end

    local minutes
    if age >= 60 then
        minutes = math.modf(age / 60)
        age = age - (minutes * 60)
    end

    local seconds = age

    local text = (days and days .. "d " or "") .. ((hours and not days) and hours .. "h " or "") .. ((minutes and not hours and not days) and minutes .. "m " or "") .. ((seconds and not minutes and not hours and not days) and seconds .. "s " or "")

    return strtrim(text)
end

-- recieves pointer to VoidMarkData VoidMark_db
function VoidMark:SetDataDb(val)
    VoidMark_db = val
end