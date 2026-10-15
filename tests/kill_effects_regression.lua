-- Run from the repository root:
-- Executed by python tests/validate.py under Lua 5.1.
-- Exercises real KillEffects.lua logic without the WoW client.

local now = 100
local plays, stops, emotes = {}, {}, {}
VoidMarkDB = {}
GetTime = function() return now end
PlaySoundFile = function(path, channel)
    assert(channel == "Master", "kill audio must use the Master channel")
    plays[#plays + 1] = path
    return true, #plays
end
StopSound = function(handle)
    stops[#stops + 1] = handle
end
DoEmote = function(token, unit)
    emotes[#emotes + 1] = { token = token, unit = unit }
end
UnitExists = function() return false end

dofile("VoidMarkForever/Compat/Forever.lua")
dofile("VoidMarkForever/KillEffects.lua")
local KE = assert(VoidMarkKillEffects)
local db = assert(VoidMarkDB.VoidMarkKillEffects)

local generic = {
    ownage = true, dominating = true, humiliation = true, killingspree = true,
    rampage = true, godlike = true, unstoppable = true, whickedsick = true,
}
local multi = {
    multikill = true, megakill = true, ultrakill = true,
    monsterkill = true, ludicrouskill = true, holyshit = true,
}
local function eq(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end
local function soundType(path)
    if not path then return "silent" end
    assert(path:find("Interface\\AddOns\\VoidMarkForever\\Sounds\\KillEffects\\", 1, true) == 1,
        "audio must load from the Forever addon folder")
    local file = path:match("([^\\]+)%.ogg$")
    if generic[file] then return "normal" end
    if multi[file] then return "multi" end
    error("Unexpected sound path: " .. tostring(path))
end
local function reset(normal, special)
    now = now + 100
    plays, stops, emotes = {}, {}, {}
    KE:OnPlayerDeath()
    KE._activeSounds = {}
    db.enabled = true
    db.killSounds = normal
    db.multiSounds = special
    db.emotes = false
end
local function kill(name, guid, delta)
    now = now + (delta or 1)
    KE:OnKill(name or "Enemy", guid)
end

-- The two sound toggles are independently authoritative at all chain lengths.
for _, test in ipairs({
    { normal = false, special = false, early = "silent", late = "silent" },
    { normal = false, special = true, early = "silent", late = "multi" },
    { normal = true, special = false, early = "normal", late = "silent" },
    { normal = true, special = true, early = "normal", late = "multi" },
}) do
    reset(test.normal, test.special)
    local expected = { test.early, test.early, test.late, test.late }
    for i = 1, 4 do
        local before = #plays
        kill("Enemy" .. i, "Player-" .. i)
        local actual = #plays > before and soundType(plays[#plays]) or "silent"
        eq(actual, expected[i],
            string.format("normal=%s multi=%s kill=%d", tostring(test.normal), tostring(test.special), i))
    end
    eq(KE:GetMultiCount(), 4, "four-kill chain count")
end

reset(true, true)
kill("A", "A")
kill("B", "B")
kill("C", "C", 21)
eq(soundType(plays[#plays]), "normal", "20-second timeout resets chain")
eq(KE:GetMultiCount(), 1, "timeout count")
KE:OnPlayerDeath()
kill("D", "D")
eq(soundType(plays[#plays]), "normal", "death resets chain")

reset(true, true)
db.enabled = false
db.emotes = true
kill("A", "A")
eq(#plays, 0, "master disables all sounds")
eq(#emotes, 0, "master disables all emotes")
db.enabled = true
db.killSounds = false
db.multiSounds = false
kill("B", "B")
eq(#plays, 0, "emote-only doesn't play audio")
eq(#emotes, 1, "emote independent from both sound toggles")

-- Feign must stop the Hunter's audio only, not a different player's sound.
reset(true, true)
kill("Hunter", "Player-Hunter")
kill("Rogue", "Player-Rogue")
eq(#plays, 2, "two simultaneous sound handles")
KE:StopActiveSound("Hunter", "Player-Hunter")
eq(#stops, 1, "one matching Hunter sound stopped")
eq(stops[1], 1, "Hunter's original handle stopped")
KE:StopActiveSound("Hunter", "Player-Different")
eq(#stops, 1, "different GUID must not stop a same-named player")
KE:StopActiveSound("Rogue", "Player-Rogue")
eq(#stops, 2, "Rogue's own handle can be stopped")
eq(stops[2], 2, "Rogue handle")

reset(true, false)
kill("Hunter-Whitemane", nil)
KE:StopActiveSound("Hunter", nil)
eq(#stops, 0, "primary-only Feign must not match a different secondary name")
KE:StopActiveSound("Hunter-Whitemane", nil)
eq(#stops, 1, "full-name Feign fallback matches its victim")

reset(true, false)
kill("Hunter-One", nil)
kill("Hunter-Two", nil)
KE:StopActiveSound("Hunter One", nil)
eq(#stops, 1, "same primary name must not merge sound victims")
eq(stops[1], 1, "display name matches its complete Forever identity")

reset(true, false)
kill("Hunter", "Player-Hunter")
now = now + 9
KE:StopActiveSound("Hunter", "Player-Hunter")
eq(#stops, 0, "expired sound must not be stopped")
KE:StopActiveSound()
eq(#stops, 0, "unspecified Feign victim must not cancel audio")

print("PASS: kill sound toggles, chain reset, emotes and victim-specific Feign cancellation")
