local VMAPI = VoidMarkForever.API
-- VoidMark Kill Effects
-- Lightweight kill sounds + optional post-kill emotes.

VoidMarkKillEffects = VoidMarkKillEffects or {}
local KE = VoidMarkKillEffects

local ADDON = "VoidMark"
local SOUND_ROOT = "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\KillEffects\\"
local MULTI_WINDOW = 20

local GENERIC_SOUNDS = {
    "ownage.ogg",
    "dominating.ogg",
    "humiliation.ogg",
    "killingspree.ogg",
    "rampage.ogg",
    "godlike.ogg",
    "unstoppable.ogg",
    "whickedsick.ogg",
}

local MULTI_SOUNDS = {
    "multikill.ogg",
    "megakill.ogg",
    "ultrakill.ogg",
    "monsterkill.ogg",
    "ludicrouskill.ogg",
    "holyshit.ogg",
}

local EMOTES = {
    { token = "BELCH", label = "Belch" },
    { token = "BOGGLE", label = "Boggle" },
    { token = "BONK", label = "Bonk" },
    { token = "BORED", label = "Bored" },
    { token = "BOUNCE", label = "Bounce" },
    { token = "BOW", label = "Bow" },
    { token = "APPLAUD", label = "Bravo" },
    { token = "BRB", label = "BRB" },
    { token = "BURP", label = "Burp" },
    { token = "BYE", label = "Bye" },
    { token = "CACKLE", label = "Cackle" },
    { token = "CALM", label = "Calm" },
    { token = "SCRATCH", label = "Cat" },
    { token = "CHEER", label = "Cheer" },
    { token = "EAT", label = "Chew" },
    { token = "CHICKEN", label = "Chicken" },
    { token = "CHUCKLE", label = "Chuckle" },
    { token = "CLAP", label = "Clap" },
    { token = "COMFORT", label = "Comfort" },
    { token = "COMMEND", label = "Commend" },
    { token = "CONFUSED", label = "Confused" },
    { token = "CONGRATULATE", label = "Congrats" },
    { token = "COUGH", label = "Cough" },
    { token = "COWER", label = "Cower" },
    { token = "CRACK", label = "Crack Knuckles" },
    { token = "CRINGE", label = "Cringe" },
    { token = "CRY", label = "Cry" },
    { token = "CUDDLE", label = "Cuddle" },
    { token = "CURIOUS", label = "Curious" },
    { token = "CURTSEY", label = "Curtsey" },
    { token = "DANCE", label = "Dance" },
    { token = "DOOM", label = "Doom" },
    { token = "DRINK", label = "Drink" },
    { token = "DROOL", label = "Drool" },
    { token = "EYE", label = "Eye" },
    { token = "FART", label = "Fart" },
    { token = "FLEX", label = "Flex" },
    { token = "FROWN", label = "Frown" },
    { token = "GASP", label = "Gasp" },
    { token = "GLARE", label = "Glare" },
    { token = "GLOAT", label = "Gloat" },
    { token = "GOLFCLAP", label = "Golf Clap" },
    { token = "GREET", label = "Greet" },
    { token = "GRIN", label = "Grin" },
    { token = "GROAN", label = "Groan" },
    { token = "GROWL", label = "Growl" },
    { token = "GUFFAW", label = "Guffaw" },
    { token = "HAIL", label = "Hail" },
    { token = "HAPPY", label = "Happy" },
    { token = "HISS", label = "Hiss" },
    { token = "HUG", label = "Hug" },
    { token = "FIDGET", label = "Impatient" },
    { token = "INSULT", label = "Insult" },
    { token = "INTRODUCE", label = "Introduce" },
    { token = "JK", label = "JK" },
    { token = "KISS", label = "Kiss" },
    { token = "KNEEL", label = "Kneel" },
    { token = "KNUCKLES", label = "Knuckles" },
    { token = "LAUGH", label = "Laugh" },
    { token = "LICK", label = "Lick" },
    { token = "LISTEN", label = "Listen" },
    { token = "LOST", label = "Lost" },
    { token = "LOVE", label = "Love" },
    { token = "ANGRY", label = "Mad" },
    { token = "MASSAGE", label = "Massage" },
    { token = "MOAN", label = "Moan" },
    { token = "MOCK", label = "Mock" },
    { token = "MOO", label = "Moo" },
    { token = "MOON", label = "Moon" },
    { token = "MOURN", label = "Mourn" },
    { token = "NO", label = "No" },
    { token = "NOD", label = "Nod" },
    { token = "NOSEPICK", label = "Nosepick" },
    { token = "PAT", label = "Pat" },
    { token = "PEER", label = "Peer" },
    { token = "SHOO", label = "Shoo" },
    { token = "PITY", label = "Pity" },
    { token = "PLEAD", label = "Plead" },
    { token = "POINT", label = "Point" },
    { token = "POKE", label = "Poke" },
    { token = "PONDER", label = "Ponder" },
    { token = "POUNCE", label = "Pounce" },
    { token = "PRAISE", label = "Praise" },
    { token = "PRAY", label = "Pray" },
    { token = "PURR", label = "Purr" },
    { token = "PUZZLE", label = "Puzzled" },
    { token = "TALKQ", label = "Question" },
    { token = "RAISE", label = "Raise" },
    { token = "RASP", label = "Rasp (Rude Gesture)" },
    { token = "READY", label = "Ready" },
    { token = "SHAKE", label = "Shake Rear" },
    { token = "ROAR", label = "Roar" },
    { token = "ROFL", label = "ROFL" },
    { token = "RUDE", label = "Rude" },
    { token = "SALUTE", label = "Salute" },
    { token = "SEXY", label = "Sexy" },
    { token = "SHIMMY", label = "Shimmy" },
    { token = "SHY", label = "Shy" },
    { token = "SIGH", label = "Sigh" },
    { token = "JOKE", label = "Silly" },
    { token = "SLAP", label = "Slap" },
    { token = "SMELL", label = "Smell" },
    { token = "SMILE", label = "Smile" },
    { token = "SMIRK", label = "Smirk" },
    { token = "SNARL", label = "Snarl" },
    { token = "SNICKER", label = "Snicker" },
    { token = "SNIFF", label = "Sniff" },
    { token = "SNUB", label = "Snub" },
    { token = "SOOTHE", label = "Soothe" },
    { token = "APOLOGIZE", label = "Sorry" },
    { token = "SPIT", label = "Spit" },
    { token = "STARE", label = "Stare" },
    { token = "SURPRISED", label = "Surprised" },
    { token = "TAP", label = "Tap" },
    { token = "TAUNT", label = "Taunt" },
    { token = "TEASE", label = "Tease" },
    { token = "THANK", label = "Thank" },
    { token = "THREATEN", label = "Threaten" },
    { token = "TICKLE", label = "Tickle" },
    { token = "TIRED", label = "Tired" },
    { token = "VETO", label = "Veto" },
    { token = "VICTORY", label = "Victory" },
    { token = "VIOLIN", label = "Violin" },
    { token = "WAVE", label = "Wave" },
    { token = "WELCOME", label = "Welcome" },
    { token = "WHINE", label = "Whine" },
    { token = "WHISTLE", label = "Whistle" },
    { token = "WINK", label = "Wink" },
    { token = "WORK", label = "Work" },
    { token = "YAWN", label = "Yawn" },
}

local function EnsureDB()
    if not VoidMarkDB then
        KE._fallback = KE._fallback or {}
        return KE._fallback
    end

    VoidMarkDB.VoidMarkKillEffects = VoidMarkDB.VoidMarkKillEffects or {}
    local db = VoidMarkDB.VoidMarkKillEffects

    if db.enabled == nil then db.enabled = true end
    if db.killSounds == nil then db.killSounds = true end
    if db.multiSounds == nil then db.multiSounds = true end
    if db.emotes == nil then db.emotes = false end

    if db.emoteMode == "default" then
        db.emoteMode = "default"
    elseif db.emoteMode == "random" then
        db.emoteMode = "favorites"
    end
    if db.emoteMode ~= "default" and db.emoteMode ~= "favorites" then
        db.emoteMode = "favorites"
    end

    db.singleEmote = tostring(db.singleEmote or "LAUGH")
    db.favoriteEmotes = type(db.favoriteEmotes) == "table" and db.favoriteEmotes or {}

    if type(db.enabledEmotes) == "table" then
        for token, enabled in pairs(db.enabledEmotes) do
            if enabled then
                db.favoriteEmotes[token] = true
            end
        end
        db.enabledEmotes = nil
    end

    local anyFavorite = false
    for _, info in ipairs(EMOTES) do
        if db.favoriteEmotes[info.token] then
            anyFavorite = true
            break
        end
    end
    if not anyFavorite then
        db.favoriteEmotes.LAUGH = true
        db.favoriteEmotes.GLOAT = true
        db.favoriteEmotes.TAUNT = true
        db.favoriteEmotes.FLEX = true
    end

    return db
end

local function PickDifferent(list, lastIndex)
    local n = #list
    if n <= 0 then return nil, nil end
    if n == 1 then return list[1], 1 end

    local idx = math.random(1, n)
    if idx == lastIndex then
        idx = (idx % n) + 1
    end
    return list[idx], idx
end

local function PlayFile(filename)
    if not filename or not PlaySoundFile then return end
    local ok, handle = PlaySoundFile(SOUND_ROOT .. filename, "Master")
    if ok and handle then
        KE._activeSoundHandle = handle
    end
end

function KE:StopActiveSound()
    local handle = self._activeSoundHandle
    self._activeSoundHandle = nil
    if handle and StopSound then
        pcall(StopSound, handle, 0)
    end
end

local function FavoriteEmoteTokens(db)
    local out = {}
    for _, info in ipairs(EMOTES) do
        if db.favoriteEmotes[info.token] then
            out[#out + 1] = info.token
        end
    end
    return out
end

local FALLBACK_EMOTES = {
    "CHEER",
    "CACKLE",
    "LAUGH",
    "GLOAT",
    "FLEX",
    "ROAR",
    "CHUCKLE",
    "CLAP",
}

local function TargetMatchesVictim(victimName, victimGUID)
    if not VMAPI.UnitExists or not VMAPI.UnitExists("target") then return false end

    if victimGUID and VMAPI.UnitGUID then
        local targetGUID = VMAPI.UnitGUID("target")
        if targetGUID and targetGUID == victimGUID then
            return true
        end
    end

    if victimName and VMAPI.UnitName then
        local targetName = VMAPI.UnitName("target")
        local want = tostring(victimName):match("^[^-]+")
        local have = targetName and tostring(targetName):match("^[^-]+")
        if want and have and want:lower() == have:lower() then
            return true
        end
    end

    return false
end

local function DoConfiguredEmote(db, victimName, victimGUID)
    if not db.emotes or not DoEmote then return end

    local token
    if db.emoteMode == "default" then
        token = db.singleEmote
    else
        local choices = FavoriteEmoteTokens(db)
        if #choices > 0 then
            token = choices[math.random(1, #choices)]
        end
    end

    if not token or token == "" then return end

    if TargetMatchesVictim(victimName, victimGUID) then
        -- Explicitly bind the emote to the actual kill target. This prevents
        -- target changes between the kill event and the emote from redirecting
        -- a BONK / TAUNT / etc. to the wrong player.
        pcall(DoEmote, token, "target")
    else
        -- No valid victim target anymore. Never let a target-dependent emote
        -- fall back onto the player ("You bonk yourself..."). Use a harmless
        -- untargeted victory emote instead.
        local fallback = FALLBACK_EMOTES[math.random(1, #FALLBACK_EMOTES)]
        pcall(DoEmote, fallback)
    end
end

function KE:OnKill(victimName, victimGUID)
    local db = EnsureDB()
    if not db.enabled then return end

    local now = GetTime and GetTime() or 0
    if (not self.lastKillAt) or (now - self.lastKillAt > MULTI_WINDOW) then
        self.multiCount = 1
    else
        self.multiCount = (tonumber(self.multiCount) or 1) + 1
    end
    self.lastKillAt = now

    if db.killSounds then
        if db.multiSounds and (tonumber(self.multiCount) or 0) >= 3 then
            local sound
            sound, self.lastMultiIndex = PickDifferent(MULTI_SOUNDS, self.lastMultiIndex)
            PlayFile(sound)
        else
            local sound
            sound, self.lastGenericIndex = PickDifferent(GENERIC_SOUNDS, self.lastGenericIndex)
            PlayFile(sound)
        end
    end

    DoConfiguredEmote(db, victimName, victimGUID)
end

function KE:OnPlayerDeath()
    self.multiCount = 0
    self.lastKillAt = nil
end

function KE:GetMultiCount()
    return tonumber(self.multiCount) or 0
end

function KE:GetMultiWindow()
    return MULTI_WINDOW
end

-- -------------------------------------------------------------------------
-- Options UI
-- -------------------------------------------------------------------------
local VM_BG = {0.015, 0.010, 0.025, 0.98}
local VM_PANEL = {0.035, 0.025, 0.055, 0.98}
local VM_BORDER = {0.31, 0.11, 0.46, 1.00}
local VM_PURPLE = {0.76, 0.42, 1.00}
local VM_FAVORITE = {1.00, 0.82, 0.18, 1.00}

local function ApplyFrame(frame, bg)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local c = bg or VM_BG
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(VM_BORDER[1], VM_BORDER[2], VM_BORDER[3], VM_BORDER[4])
end

local function MakeButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    ApplyFrame(b, VM_PANEL)
    b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Label:SetPoint("CENTER")
    b.Label:SetText(text)
    b.Label:SetTextColor(0.88, 0.78, 0.94, 1)
    return b
end

local function MakeCheck(parent, label, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    fs:SetTextColor(0.86, 0.76, 0.92, 1)
    cb.Label = fs
    return cb
end

local function EmoteLabel(token)
    for _, info in ipairs(EMOTES) do
        if info.token == token then return info.label end
    end
    return tostring(token or "Laugh")
end

local function FavoriteCount(db)
    local n = 0
    for _, info in ipairs(EMOTES) do
        if db.favoriteEmotes[info.token] then n = n + 1 end
    end
    return n
end

local function BuildOptions()
    if KE.OptionsFrame then return KE.OptionsFrame end

    local f = CreateFrame("Frame", "VoidMarkKillEffectsOptions", UIParent, "BackdropTemplate")
    KE.OptionsFrame = f
    f:SetSize(390, 285)
    f:SetPoint("CENTER", UIParent, "CENTER", 440, 80)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    ApplyFrame(f, VM_BG)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText("VOIDMARK  •  KILL EFFECTS")
    title:SetTextColor(VM_PURPLE[1], VM_PURPLE[2], VM_PURPLE[3], 1)

    local close = MakeButton(f, "X", 22, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    help:SetWidth(360)
    help:SetJustifyH("LEFT")
    help:SetText("1–2 kills use random flavor sounds. At 3+ kills, each kill inside a 20 sec chain randomly uses a multi-kill sound.")
    help:SetTextColor(0.62, 0.55, 0.68, 1)

    f.Enabled = MakeCheck(f, "KILL EFFECTS", 12, -76)
    f.KillSounds = MakeCheck(f, "KILL SOUNDS", 12, -106)
    f.MultiSounds = MakeCheck(f, "3+ MULTI-KILL SOUNDS", 198, -106)
    f.Emotes = MakeCheck(f, "POST-KILL EMOTE", 12, -136)

    local modeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    modeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -174)
    modeLabel:SetText("Emote mode")
    modeLabel:SetTextColor(0.62, 0.55, 0.68, 1)

    f.Mode = MakeButton(f, "RANDOM FAVS", 118, 22)
    f.Mode:SetPoint("TOPLEFT", f, "TOPLEFT", 92, -168)

    local emoteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emoteLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -205)
    emoteLabel:SetText("Emote")
    emoteLabel:SetTextColor(0.62, 0.55, 0.68, 1)

    f.EmoteDrop = MakeButton(f, "Laugh  v", 160, 22)
    f.EmoteDrop:SetPoint("TOPLEFT", f, "TOPLEFT", 92, -199)

    f.FavText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.FavText:SetPoint("LEFT", f.EmoteDrop, "RIGHT", 10, 0)
    f.FavText:SetTextColor(VM_FAVORITE[1], VM_FAVORITE[2], VM_FAVORITE[3], 1)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -232)
    hint:SetWidth(355)
    hint:SetJustifyH("LEFT")
    hint:SetText("Click = set default   •   Shift-click = favorite/unfavorite")
    hint:SetTextColor(0.62, 0.55, 0.68, 1)

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    footer:SetText("Multi-kill chain window: 20 seconds")
    footer:SetTextColor(0.55, 0.48, 0.62, 1)

    local pop = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.Dropdown = pop
    pop:SetSize(250, 286)
    pop:SetPoint("TOPLEFT", f.EmoteDrop, "BOTTOMLEFT", 0, -2)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(f:GetFrameLevel() + 20)
    pop:EnableMouse(true)
    pop:EnableMouseWheel(true)
    pop:SetClampedToScreen(true)
    ApplyFrame(pop, VM_BG)
    pop:Hide()

    local rows = {}
    local visibleRows = 13
    local rowHeight = 20
    local offset = 1

    local scrollText = pop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scrollText:SetPoint("BOTTOM", pop, "BOTTOM", 0, 5)
    scrollText:SetText("Mouse wheel to scroll")
    scrollText:SetTextColor(0.50, 0.45, 0.56, 1)

    local function RefreshDropdown()
        local db = EnsureDB()
        local maxOffset = math.max(1, #EMOTES - visibleRows + 1)
        if offset > maxOffset then offset = maxOffset end
        if offset < 1 then offset = 1 end

        for i = 1, visibleRows do
            local info = EMOTES[offset + i - 1]
            local row = rows[i]
            if info then
                row.info = info
                row:Show()
                local favorite = db.favoriteEmotes[info.token] and true or false
                local selected = (db.singleEmote == info.token)
                local prefix = favorite and "* " or "  "
                local suffix = selected and "   [DEFAULT]" or ""
                row.Label:SetText(prefix .. info.label .. suffix)
                if favorite then
                    row.Label:SetTextColor(VM_FAVORITE[1], VM_FAVORITE[2], VM_FAVORITE[3], 1)
                elseif selected then
                    row.Label:SetTextColor(VM_PURPLE[1], VM_PURPLE[2], VM_PURPLE[3], 1)
                else
                    row.Label:SetTextColor(0.88, 0.82, 0.92, 1)
                end
            else
                row.info = nil
                row:Hide()
            end
        end
    end

    for i = 1, visibleRows do
        local row = CreateFrame("Button", nil, pop)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -7 - ((i - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -7 - ((i - 1) * rowHeight))
        row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.Label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.Label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.Label:SetJustifyH("LEFT")
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row:SetScript("OnClick", function(self)
            if not self.info then return end
            local db = EnsureDB()
            if IsShiftKeyDown and IsShiftKeyDown() then
                if db.favoriteEmotes[self.info.token] then
                    db.favoriteEmotes[self.info.token] = nil
                else
                    db.favoriteEmotes[self.info.token] = true
                end
                if f.Refresh then f:Refresh() end
                RefreshDropdown()
            else
                db.singleEmote = self.info.token
                if f.Refresh then f:Refresh() end
                pop:Hide()
            end
        end)
        rows[i] = row
    end

    pop:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(1, #EMOTES - visibleRows + 1)
        if delta > 0 then
            offset = math.max(1, offset - 4)
        else
            offset = math.min(maxOffset, offset + 4)
        end
        RefreshDropdown()
    end)

    local function Refresh()
        local db = EnsureDB()
        f.Enabled:SetChecked(db.enabled)
        f.KillSounds:SetChecked(db.killSounds)
        f.MultiSounds:SetChecked(db.multiSounds)
        f.Emotes:SetChecked(db.emotes)
        f.Mode.Label:SetText(db.emoteMode == "default" and "DEFAULT" or "RANDOM FAVS")
        f.EmoteDrop.Label:SetText(EmoteLabel(db.singleEmote) .. "  v")
        f.FavText:SetText(string.format("%d favorites", FavoriteCount(db)))
        if pop:IsShown() then RefreshDropdown() end
    end
    f.Refresh = Refresh

    f.Enabled:SetScript("OnClick", function(self) EnsureDB().enabled = self:GetChecked() and true or false end)
    f.KillSounds:SetScript("OnClick", function(self) EnsureDB().killSounds = self:GetChecked() and true or false end)
    f.MultiSounds:SetScript("OnClick", function(self) EnsureDB().multiSounds = self:GetChecked() and true or false end)
    f.Emotes:SetScript("OnClick", function(self) EnsureDB().emotes = self:GetChecked() and true or false end)

    f.Mode:SetScript("OnClick", function()
        local db = EnsureDB()
        db.emoteMode = (db.emoteMode == "default") and "favorites" or "default"
        Refresh()
    end)

    f.EmoteDrop:SetScript("OnClick", function()
        if pop:IsShown() then
            pop:Hide()
        else
            offset = 1
            local db = EnsureDB()
            for i, info in ipairs(EMOTES) do
                if info.token == db.singleEmote then
                    offset = math.max(1, math.min(i - 3, #EMOTES - visibleRows + 1))
                    break
                end
            end
            RefreshDropdown()
            pop:Show()
        end
    end)

    f:SetScript("OnHide", function()
        pop:Hide()
    end)

    f:Hide()
    return f
end

function KE:ToggleOptions()
    local f = BuildOptions()
    if f:IsShown() then
        f:Hide()
    else
        if f.Refresh then f:Refresh() end
        f:Show()
    end
end

EnsureDB()
