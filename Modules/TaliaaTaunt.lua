local VMAPI = VoidMarkForever.API
-- Taliaa Taunt
-- Compact Classic Era cross-faction translator + saved quick phrases. VoidMark-inspired UI.
-- VoidMark integrated module: compact enemy preview; legacy notice bar removed.

local addonName = ...
local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local MAX_PHRASES = 40
local ROW_HEIGHT = 28
local NOTICE_HOLD_SECONDS = 10
local NOTICE_FADE_SECONDS = 1.5
local FLASH_HOLD_SECONDS = 3.0
local FLASH_FADE_SECONDS = 0.55
local VISIBLE_ROWS = 5
local MINI_VISIBLE_PHRASES = 4

-- VoidMark-inspired palette: near-black surfaces with restrained violet accents.
local VOID = {
    bg = { 0.015, 0.010, 0.025, 0.96 },
    panel = { 0.030, 0.018, 0.045, 0.94 },
    panelSoft = { 0.045, 0.026, 0.065, 0.82 },
    purple = { 0.46, 0.13, 0.72, 1.00 },
    bright = { 0.72, 0.35, 1.00, 1.00 },
    text = { 0.94, 0.91, 0.98, 1.00 },
    muted = { 0.62, 0.56, 0.68, 1.00 },
}

-- Language dictionaries retained from the working translator.
local COMMON = {
    LanguageID = 7,
    ALPHABET = {
        { 'A', '€' }, { 'B', '῁' }, { 'D', '🵐' }, { 'E', '4' }, { 'F', 'Ἆ' }, { 'G', '🟰' },
        { 'H', '༫' }, { 'I', '0' }, { 'K', 'Š' }, { 'L', 'ⶎ' }, { 'M', 'Ä' }, { 'N', '🤭' },
        { 'O', '6' }, { 'R', '‡' }, { 'S', 'Ğ' }, { 'T', '🻂' }, { 'U', '򧏭' }, { 'V', 'Ё' },
        { 'W', 'Ἠ' }, { 'Y', '3' }, { 'P', 'Þ' }, { 'X', '×' }
    },
    SUBSTITUTES = { C = 'K', J = 'G', Q = 'K', Z = 'S' },
    SEPARATOR = { INPUT = '_', OUTPUT = '_' },
    Name = 'Common'
}

local ORCISH = {
    LanguageID = 1,
    ALPHABET = {
        { 'MU', 'AZ' }, { 'IL', '44' }, { 'A', '1' }, { 'D', '🷙' }, { 'G', 'A' }, { 'H', 'Ɣ' },
        { 'I', 'Ȋ' }, { 'K', 'ཎ' }, { 'L', 'D' }, { 'M', 'ா' }, { 'N', 'J' }, { 'O', 'C' },
        { 'R', '' }, { 'T', 'ධ' }, { 'U', '🝥' }, { 'Z', 'ড়' }, { 'C', '¢' }, { 'E', '£' },
        { 'V', '\\/' }, { 'W', '\\/\\/' }, { 'Y', '¥' }, { 'P', 'Þ' }, { 'X', '×' }
    },
    SUBSTITUTES = { B = 'H', F = 'TH', J = 'G', Q = 'K', S = 'Z' },
    SEPARATOR = { INPUT = '_', OUTPUT = '_' },
    Name = 'Orcish'
}

local TAURAHE = {
    LanguageID = 3,
    ALPHABET = {
        { 'A', '𓃛' }, { 'B', 'ʅ' }, { 'C', 'ਭ' }, { 'E', '𐭌' }, { 'H', '𓂮' }, { 'I', '𐫵' },
        { 'K', 'М' }, { 'L', 'ǹ' }, { 'M', '𐠪' }, { 'N', '𓀻' }, { 'O', 'ਧ' }, { 'P', '΁' },
        { 'R', 'ꬁ' }, { 'S', '𓂂' }, { 'T', '𓂀' }, { 'U', '꛶' }, { 'W', 'ҧ' }, { 'Z', '਋' },
        { 'V', '\\/' }, { 'X', '×' }, { 'Y', '¥' }
    },
    SUBSTITUTES = { D = 'B', F = 'PH', G = 'K', Q = 'K' },
    SEPARATOR = { INPUT = '_', OUTPUT = '_' },
    Name = 'Taurahe'
}

local UNDEAD = {
    LanguageID = 33,
    ALPHABET = {
        { 'A', '7' }, { 'B', '㪴' }, { 'D', '🭭' }, { 'E', '0' }, { 'F', 'ኡ' }, { 'G', '🨜' },
        { 'H', '༯' }, { 'I', 'P' }, { 'K', 'À' }, { 'L', 'ᎆ' }, { 'M', 'Ý' }, { 'N', 'Í' },
        { 'O', '2' }, { 'R', 'ⶎ' }, { 'S', 'ߢ' }, { 'T', '👶' }, { 'U', '1' }, { 'V', '‡' },
        { 'W', 'ཽ' }, { 'Y', '¥' }, { 'X', '×' }, { 'P', 'Þ' }
    },
    SUBSTITUTES = { C = 'K', J = 'G', Q = 'K', Z = 'S' },
    SEPARATOR = { INPUT = '_', OUTPUT = '_' },
    Name = 'Gutterspeak'
}

local ZANDALI = {
    LanguageID = 14,
    ALPHABET = {
        { 'BW', '᾵ᢴ' }, { 'IT', 'Ⴠᩝ' }, { 'IM', 'ɍʯ' }, { 'A', 'A' }, { 'C', '🚫' },
        { 'D', '㎠' }, { 'E', 'M' }, { 'F', 'Ǜ' }, { 'H', 'N' }, { 'I', '🹈' }, { 'J', 'F' },
        { 'M', 'O' }, { 'N', 'Q' }, { 'O', 'D' }, { 'R', '🅎' }, { 'S', '9' }, { 'T', '👶' },
        { 'U', '0' }, { 'W', 'ᎆ' }, { 'Y', '🼃' }, { 'P', 'Þ' }, { 'V', '\\/' }, { 'L', '🹈_' }
    },
    SUBSTITUTES = { B = 'BW', G = 'J', K = 'C', Q = 'C', X = 'W', Z = 'W' },
    SEPARATOR = { INPUT = ' ', OUTPUT = ' ' },
    Name = 'Zandali'
}

local LANGUAGE_MODES = {
    { value = 'AUTO', label = 'Auto' },
    { value = 'ORCISH', label = 'Orcish' },
    { value = 'GUTTERSPEAK', label = 'Gutterspeak' },
}

local function Print(msg)
    print('|cFFB56CFF[Taliaa Taunt]|r ' .. msg)
end

local function Trim(text)
    return (text or ''):match('^%s*(.-)%s*$')
end

local function AutoDictionary()
    local _, raceEN = VMAPI.UnitRace('player')
    local faction = VMAPI.UnitFactionGroup('player')

    if faction == 'Alliance' then
        return COMMON
    end

    if faction == 'Horde' then
        if raceEN == 'Undead' or raceEN == 'Scourge' or raceEN == 'Forsaken' then
            return UNDEAD
        elseif raceEN == 'Troll' then
            return ZANDALI
        elseif raceEN == 'Tauren' then
            return TAURAHE
        end
        return ORCISH
    end

    return nil
end

local function ChooseDictionary()
    local mode = TaliaaTauntDB and TaliaaTauntDB.languageMode or 'AUTO'
    if mode == 'ORCISH' then return ORCISH end
    if mode == 'GUTTERSPEAK' then return UNDEAD end
    return AutoDictionary()
end

-- Returns encoded text to send and a clean human-readable approximation of what the enemy sees.
local function Translate(msg, dictionary)
    if not msg or msg == '' then return '', '' end
    if not dictionary or not dictionary.ALPHABET or not dictionary.SUBSTITUTES then
        return msg, msg
    end

    local youSay, theySee = '', ''
    local raw = string.upper(string.gsub(msg, '\\', '{{BACKSLASH}}'))

    while #raw > 0 do
        local found = false
        local bestLen, bestVal, bestKey = 0, nil, nil

        for _, pair in ipairs(dictionary.ALPHABET) do
            local key, val = pair[1], pair[2]
            if #key > 1 then
                local escaped = string.gsub(key, '([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
                if string.find(raw, '^' .. escaped) and #key > bestLen then
                    bestLen, bestVal, bestKey = #key, val, key
                end
            end
        end

        if bestLen > 0 then
            youSay = youSay .. bestVal .. ' '
            theySee = theySee .. bestKey
            raw = string.sub(raw, bestLen + 1)
            found = true
        end

        if not found then
            for _, pair in ipairs(dictionary.ALPHABET) do
                local key, val = pair[1], pair[2]
                if #key == 1 then
                    local escaped = string.gsub(key, '([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
                    if string.find(raw, '^' .. escaped) then
                        youSay = youSay .. val .. ' '
                        theySee = theySee .. key
                        raw = string.sub(raw, 2)
                        found = true
                        break
                    end
                end
            end
        end

        if not found then
            for key, val in pairs(dictionary.SUBSTITUTES) do
                local escaped = string.gsub(key, '([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
                if string.find(raw, '^' .. escaped) then
                    raw = string.gsub(raw, '^' .. escaped, val, 1)
                    found = true
                    break
                end
            end
        end

        if not found and string.find(raw, '^%s') then
            local sepIn = (dictionary.SEPARATOR and dictionary.SEPARATOR.INPUT) or '_'
            youSay = youSay .. sepIn .. ' '
            theySee = theySee .. ' '
            raw = string.sub(raw, 2)
            found = true
        end

        if not found and string.find(raw, '^{{BACKSLASH}}') then
            youSay = youSay .. '\\ '
            theySee = theySee .. '\\'
            raw = string.sub(raw, 14)
            found = true
        end

        if not found then
            raw = string.sub(raw, 2)
        end
    end

    youSay = string.gsub(youSay, '%s+$', '')
    theySee = string.gsub(theySee, '%s+$', '')
    return youSay, theySee
end

local noticeFrame
local flashFrame
local frame
local phraseRows = {}
local miniPhraseButtons = {}

local function EnsureDB()
    TaliaaTauntDB = TaliaaTauntDB or {}
    if type(TaliaaTauntDB.quickPhrases) ~= 'table' then
        TaliaaTauntDB.quickPhrases = {}
    end
    if TaliaaTauntDB.languageMode ~= 'AUTO'
        and TaliaaTauntDB.languageMode ~= 'ORCISH'
        and TaliaaTauntDB.languageMode ~= 'GUTTERSPEAK' then
        TaliaaTauntDB.languageMode = 'AUTO'
    end
    if type(TaliaaTauntDB.echoParty) ~= 'boolean' then
        TaliaaTauntDB.echoParty = false
    end
    if type(TaliaaTauntDB.echoSay) ~= 'boolean' then
        TaliaaTauntDB.echoSay = false
    end
end

local function AddSolidBorder(target, color, thickness)
    thickness = thickness or 1
    local c = color or VOID.purple

    target._ttBorders = target._ttBorders or {}
    if #target._ttBorders > 0 then return end

    local top = target:CreateTexture(nil, 'BORDER')
    top:SetColorTexture(c[1], c[2], c[3], c[4])
    top:SetPoint('TOPLEFT')
    top:SetPoint('TOPRIGHT')
    top:SetHeight(thickness)

    local bottom = target:CreateTexture(nil, 'BORDER')
    bottom:SetColorTexture(c[1], c[2], c[3], c[4])
    bottom:SetPoint('BOTTOMLEFT')
    bottom:SetPoint('BOTTOMRIGHT')
    bottom:SetHeight(thickness)

    local left = target:CreateTexture(nil, 'BORDER')
    left:SetColorTexture(c[1], c[2], c[3], c[4])
    left:SetPoint('TOPLEFT', 0, -thickness)
    left:SetPoint('BOTTOMLEFT', 0, thickness)
    left:SetWidth(thickness)

    local right = target:CreateTexture(nil, 'BORDER')
    right:SetColorTexture(c[1], c[2], c[3], c[4])
    right:SetPoint('TOPRIGHT', 0, -thickness)
    right:SetPoint('BOTTOMRIGHT', 0, thickness)
    right:SetWidth(thickness)

    target._ttBorders = { top, bottom, left, right }
end

local function StylePanel(target, color, borderColor, thickness)
    target._ttBackground = target._ttBackground or target:CreateTexture(nil, 'BACKGROUND')
    target._ttBackground:SetAllPoints()
    local c = color or VOID.panel
    target._ttBackground:SetColorTexture(c[1], c[2], c[3], c[4])
    AddSolidBorder(target, borderColor or VOID.purple, thickness or 1)
end

local function CreateVoidButton(parent, width, height, text)
    local b = CreateFrame('Button', nil, parent)
    b:SetSize(width, height)
    StylePanel(b, VOID.panelSoft, VOID.purple, 1)

    b.label = b:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    b.label:SetPoint('CENTER', 0, 0)
    b.label:SetText(text or '')
    b.label:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], VOID.text[4])

    b:SetScript('OnEnter', function(self)
        self._ttBackground:SetColorTexture(VOID.purple[1], VOID.purple[2], VOID.purple[3], 0.68)
        self.label:SetTextColor(1, 1, 1, 1)
    end)
    b:SetScript('OnLeave', function(self)
        self._ttBackground:SetColorTexture(VOID.panelSoft[1], VOID.panelSoft[2], VOID.panelSoft[3], VOID.panelSoft[4])
        self.label:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], VOID.text[4])
    end)

    function b:SetButtonText(value)
        self.label:SetText(value or '')
    end

    return b
end

local function SaveFramePosition(target, dbKey)
    if not target or not TaliaaTauntDB then return end
    local point, _, relativePoint, x, y = target:GetPoint(1)
    if not point then return end
    TaliaaTauntDB[dbKey] = {
        point = point,
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or 0,
    }
end

local function RestoreFramePosition(target, dbKey, fallbackPoint, fallbackX, fallbackY)
    target:ClearAllPoints()
    local pos = TaliaaTauntDB and TaliaaTauntDB[dbKey]
    if type(pos) == 'table' and pos.point then
        target:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    else
        target:SetPoint(fallbackPoint or 'CENTER', UIParent, fallbackPoint or 'CENTER', fallbackX or 0, fallbackY or 0)
    end
end

local function CurrentDictionaryLabel()
    local dictionary = ChooseDictionary()
    return dictionary and dictionary.Name or '?'
end

local function CreateNoticeFrame()
    if noticeFrame then return noticeFrame end

    noticeFrame = CreateFrame('Frame', 'TaliaaTauntNoticeFrame', UIParent)
    noticeFrame:SetSize(360, 28)
    noticeFrame:SetFrameStrata('DIALOG')
    noticeFrame:SetMovable(true)
    noticeFrame:EnableMouse(true)
    noticeFrame:RegisterForDrag('LeftButton')
    noticeFrame:SetClampedToScreen(true)
    StylePanel(noticeFrame, { VOID.bg[1], VOID.bg[2], VOID.bg[3], 0.82 }, VOID.purple, 1)

    noticeFrame.channel = noticeFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    noticeFrame.channel:SetPoint('LEFT', 8, 0)
    noticeFrame.channel:SetWidth(42)
    noticeFrame.channel:SetJustifyH('LEFT')
    noticeFrame.channel:SetTextColor(VOID.bright[1], VOID.bright[2], VOID.bright[3], 1)

    noticeFrame.sep = noticeFrame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    noticeFrame.sep:SetPoint('LEFT', noticeFrame.channel, 'RIGHT', 2, 0)
    noticeFrame.sep:SetText('|')
    noticeFrame.sep:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 1)

    noticeFrame.text = noticeFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    noticeFrame.text:SetPoint('LEFT', noticeFrame.sep, 'RIGHT', 8, 0)
    noticeFrame.text:SetPoint('RIGHT', -8, 0)
    noticeFrame.text:SetJustifyH('LEFT')
    noticeFrame.text:SetWordWrap(false)
    noticeFrame.text:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], 1)

    noticeFrame:SetScript('OnDragStart', function(self)
        self:StartMoving()
    end)
    noticeFrame:SetScript('OnDragStop', function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self, 'noticePosition')
    end)

    noticeFrame:SetScript('OnUpdate', function(self)
        if not self.expiresAt then return end

        local now = GetTime()
        if now <= self.expiresAt then
            self:SetAlpha(1)
            return
        end

        local fadeElapsed = now - self.expiresAt
        if fadeElapsed >= NOTICE_FADE_SECONDS then
            self.expiresAt = nil
            self:Hide()
            self:SetAlpha(1)
            return
        end

        self:SetAlpha(1 - (fadeElapsed / NOTICE_FADE_SECONDS))
    end)

    RestoreFramePosition(noticeFrame, 'noticePosition', 'BOTTOMLEFT', 24, 190)
    noticeFrame:Hide()
    return noticeFrame
end

local function CreateFlashFrame()
    if flashFrame then return flashFrame end

    flashFrame = CreateFrame('Frame', 'TaliaaTauntEnemyFlashFrame', UIParent)
    flashFrame:SetSize(310, 48)
    flashFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 115)
    flashFrame:SetFrameStrata('FULLSCREEN_DIALOG')
    flashFrame:EnableMouse(false)
    StylePanel(flashFrame, { VOID.bg[1], VOID.bg[2], VOID.bg[3], 0.70 }, VOID.bright, 1)

    flashFrame.label = flashFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    flashFrame.label:SetPoint('TOP', 0, -5)
    flashFrame.label:SetText('ENEMY SEES')
    flashFrame.label:SetTextColor(VOID.bright[1], VOID.bright[2], VOID.bright[3], 1)

    flashFrame.text = flashFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    flashFrame.text:SetPoint('TOPLEFT', 8, -20)
    flashFrame.text:SetPoint('BOTTOMRIGHT', -8, 5)
    flashFrame.text:SetJustifyH('CENTER')
    flashFrame.text:SetJustifyV('MIDDLE')
    flashFrame.text:SetWordWrap(false)
    flashFrame.text:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], 1)

    flashFrame:SetScript('OnUpdate', function(self)
        if not self.expiresAt then return end

        local now = GetTime()
        if now <= self.expiresAt then
            self:SetAlpha(1)
            return
        end

        local fadeElapsed = now - self.expiresAt
        if fadeElapsed >= FLASH_FADE_SECONDS then
            self.expiresAt = nil
            self:Hide()
            self:SetAlpha(1)
            return
        end

        self:SetAlpha(1 - (fadeElapsed / FLASH_FADE_SECONDS))
    end)

    flashFrame:Hide()
    return flashFrame
end

local function ShowSentNotice(enemySees)
    -- Integrated VoidMark build intentionally suppresses the old top-left
    -- "SEES | ..." notice bar. The compact center preview below is the
    -- single enemy-side confirmation surface.
    return
end

local function ShowEnemyFlash(enemySees)
    local f = CreateFlashFrame()
    f.text:SetText(enemySees ~= '' and enemySees or '?')
    f.expiresAt = GetTime() + FLASH_HOLD_SECONDS
    f:SetAlpha(1)
    f:Show()
end

local function SendReadableEcho(enemySees)
    EnsureDB()

    -- Echo the enemy-side readable text for friendly players. These are independent
    -- from the encoded cross-faction taunt and are opt-in to avoid chat spam.
    local text = Trim(enemySees or '')
    if text == '' then return end

    if TaliaaTauntDB.echoParty and IsInGroup and IsInGroup() then
        SendChat(text, 'PARTY')
    end

    if TaliaaTauntDB.echoSay then
        SendChat(text, 'SAY')
    end
end

local function SendTranslated(message, channel)
    message = Trim(message)
    if message == '' then
        Print(channel == 'YELL' and 'Usage: /ty <message>' or 'Usage: /ts <message>')
        return
    end

    local dictionary = ChooseDictionary()
    if not dictionary then
        Print('Could not determine your language.')
        return
    end

    local translated, enemySees = Translate(message, dictionary)
    if translated == '' then
        Print('Nothing to send.')
        return
    end

    if #translated > 255 then
        Print('That phrase is too long after translation.')
        return
    end

    SendChat(translated, channel, dictionary.LanguageID)
    SendReadableEcho(enemySees)
    ShowEnemyFlash(enemySees)
    ShowSentNotice(enemySees)
end

local function UpdatePreview()
    if not frame or not frame.preview then return end
    local text = Trim(frame.input:GetText())
    local languageName = CurrentDictionaryLabel()

    if text == '' then
        frame.preview:SetText('Enemy sees: —   |   ' .. languageName)
        return
    end

    local dictionary = ChooseDictionary()
    if not dictionary then
        frame.preview:SetText('Enemy sees: ?')
        return
    end

    local _, enemySees = Translate(text, dictionary)
    frame.preview:SetText('Enemy sees: ' .. (enemySees ~= '' and enemySees or '?') .. '   |   ' .. languageName)
end

local function ShortPhraseLabel(text, maxChars)
    text = Trim(text)
    maxChars = maxChars or 12
    if #text <= maxChars then return text end
    return string.sub(text, 1, math.max(1, maxChars - 3)) .. '...'
end

local function RefreshMiniBar()
    if not frame or not frame.miniBar then return end
    EnsureDB()

    local phrases = TaliaaTauntDB.quickPhrases
    local shown = math.min(#phrases, MINI_VISIBLE_PHRASES)

    frame.miniEmpty:SetShown(shown == 0)

    for i = 1, MINI_VISIBLE_PHRASES do
        local button = miniPhraseButtons[i]
        if not button then
            button = CreateVoidButton(frame.miniBar, 86, 22, '')
            if i == 1 then
                button:SetPoint('LEFT', 5, 0)
            else
                button:SetPoint('LEFT', miniPhraseButtons[i - 1], 'RIGHT', 5, 0)
            end
            miniPhraseButtons[i] = button
        end

        if i <= shown then
            local index = i
            local phrase = phrases[index]
            button:SetButtonText(ShortPhraseLabel(phrase, 13))
            button:SetScript('OnClick', function()
                local channel = IsShiftKeyDown() and 'SAY' or 'YELL'
                SendTranslated(TaliaaTauntDB.quickPhrases[index], channel)
            end)
            button:SetScript('OnEnter', function(self)
                self._ttBackground:SetColorTexture(VOID.purple[1], VOID.purple[2], VOID.purple[3], 0.68)
                self.label:SetTextColor(1, 1, 1, 1)
                GameTooltip:SetOwner(self, 'ANCHOR_TOP')
                GameTooltip:SetText(TaliaaTauntDB.quickPhrases[index] or '')
                GameTooltip:AddLine('Click = YELL  •  Shift-click = SAY', 0.85, 0.75, 0.95)
                GameTooltip:Show()
            end)
            button:SetScript('OnLeave', function(self)
                self._ttBackground:SetColorTexture(VOID.panelSoft[1], VOID.panelSoft[2], VOID.panelSoft[3], VOID.panelSoft[4])
                self.label:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], VOID.text[4])
                GameTooltip:Hide()
            end)
            button:Show()
        else
            button:Hide()
        end
    end
end

local function RefreshRows()
    if not frame then return end
    EnsureDB()

    local phrases = TaliaaTauntDB.quickPhrases
    local content = frame.scrollChild
    local width = frame.scroll:GetWidth()

    for i = 1, #phrases do
        local row = phraseRows[i]
        if not row then
            row = CreateFrame('Frame', nil, content)
            row:SetHeight(ROW_HEIGHT)
            StylePanel(row, { VOID.panelSoft[1], VOID.panelSoft[2], VOID.panelSoft[3], 0.60 }, { VOID.purple[1], VOID.purple[2], VOID.purple[3], 0.50 }, 1)

            row.text = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
            row.text:SetPoint('LEFT', 7, 0)
            row.text:SetJustifyH('LEFT')
            row.text:SetWordWrap(false)
            row.text:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], 1)

            row.send = CreateVoidButton(row, 48, 22, 'YELL')
            row.delete = CreateVoidButton(row, 22, 22, 'x')

            row.delete:SetPoint('RIGHT', -3, 0)
            row.send:SetPoint('RIGHT', row.delete, 'LEFT', -4, 0)
            row.text:SetPoint('RIGHT', row.send, 'LEFT', -8, 0)

            phraseRows[i] = row
        end

        local index = i
        row:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', 0, -((i - 1) * ROW_HEIGHT))
        row.text:SetText(phrases[i])
        row.send:SetScript('OnClick', function()
            local channel = IsShiftKeyDown() and 'SAY' or 'YELL'
            SendTranslated(TaliaaTauntDB.quickPhrases[index], channel)
        end)
        row.delete:SetScript('OnClick', function()
            table.remove(TaliaaTauntDB.quickPhrases, index)
            RefreshRows()
        end)
        row:Show()
    end

    for i = #phrases + 1, #phraseRows do
        phraseRows[i]:Hide()
    end

    local totalHeight = math.max(1, #phrases * ROW_HEIGHT)
    content:SetHeight(totalHeight)

    local maxScroll = math.max(0, totalHeight - frame.scroll:GetHeight())
    local current = frame.scroll:GetVerticalScroll() or 0
    if current > maxScroll then
        frame.scroll:SetVerticalScroll(maxScroll)
    end

    RefreshMiniBar()
end

local function SavePhrase()
    EnsureDB()
    if not frame then return end

    local phrase = Trim(frame.input:GetText())
    if phrase == '' then return end

    if #TaliaaTauntDB.quickPhrases >= MAX_PHRASES then
        Print('Quick phrase list is full (' .. MAX_PHRASES .. ').')
        return
    end

    for _, existing in ipairs(TaliaaTauntDB.quickPhrases) do
        if string.upper(existing) == string.upper(phrase) then
            Print('That quick phrase is already saved.')
            return
        end
    end

    table.insert(TaliaaTauntDB.quickPhrases, phrase)
    frame.input:SetText('')
    frame.input:ClearFocus()
    RefreshRows()
    UpdatePreview()
end

local function LanguageModeLabel(mode)
    for _, option in ipairs(LANGUAGE_MODES) do
        if option.value == mode then return option.label end
    end
    return 'Auto'
end

local function RefreshLanguageButton()
    if not frame or not frame.languageButton then return end
    frame.languageButton:SetButtonText(LanguageModeLabel(TaliaaTauntDB.languageMode or 'AUTO'))
end

local function CycleLanguageMode()
    EnsureDB()
    local current = TaliaaTauntDB.languageMode or 'AUTO'
    local nextMode = 'AUTO'

    if current == 'AUTO' then
        nextMode = 'ORCISH'
    elseif current == 'ORCISH' then
        nextMode = 'GUTTERSPEAK'
    end

    TaliaaTauntDB.languageMode = nextMode
    RefreshLanguageButton()
    UpdatePreview()
end

local function RefreshEchoButtons()
    if not frame then return end
    EnsureDB()
    if frame.echoParty then
        frame.echoParty:SetButtonText((TaliaaTauntDB.echoParty and '[x] ' or '[ ] ') .. 'Party')
    end
    if frame.echoSay then
        frame.echoSay:SetButtonText((TaliaaTauntDB.echoSay and '[x] ' or '[ ] ') .. 'Say')
    end
end

local function ToggleEchoParty()
    EnsureDB()
    TaliaaTauntDB.echoParty = not TaliaaTauntDB.echoParty
    RefreshEchoButtons()
end

local function ToggleEchoSay()
    EnsureDB()
    TaliaaTauntDB.echoSay = not TaliaaTauntDB.echoSay
    RefreshEchoButtons()
end

local function SetMinimized(minimized)
    if not frame then return end
    frame.minimized = minimized and true or false
    EnsureDB()
    TaliaaTauntDB.minimized = frame.minimized

    if frame.minimized then
        frame.content:Hide()
        frame.miniBar:Show()
        frame:SetHeight(58)
        frame.minimize:SetButtonText('+')
        RefreshMiniBar()
    else
        frame.miniBar:Hide()
        frame:SetHeight(frame.expandedHeight)
        frame.content:Show()
        frame.minimize:SetButtonText('-')
        RefreshRows()
        UpdatePreview()
    end
end

local function CreateMainFrame()
    if frame then return frame end

    frame = CreateFrame('Frame', 'TaliaaTauntFrame', UIParent)
    frame:SetSize(392, 270)
    frame.expandedHeight = 270
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetClampedToScreen(true)
    frame:SetScript('OnDragStart', function(self)
        if self.minimized then self:StartMoving() end
    end)
    frame:SetScript('OnDragStop', function(self)
        if self.minimized then
            self:StopMovingOrSizing()
            SaveFramePosition(self, 'windowPosition')
        end
    end)
    StylePanel(frame, VOID.bg, VOID.purple, 1)

    frame.titleBar = CreateFrame('Frame', nil, frame)
    frame.titleBar:SetPoint('TOPLEFT', 1, -1)
    frame.titleBar:SetPoint('TOPRIGHT', -1, -1)
    frame.titleBar:SetHeight(26)
    frame.titleBar:EnableMouse(true)
    frame.titleBar:RegisterForDrag('LeftButton')
    frame.titleBar:SetScript('OnDragStart', function()
        frame:StartMoving()
    end)
    frame.titleBar:SetScript('OnDragStop', function()
        frame:StopMovingOrSizing()
        SaveFramePosition(frame, 'windowPosition')
    end)

    local titleBg = frame.titleBar:CreateTexture(nil, 'BACKGROUND')
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(VOID.panel[1], VOID.panel[2], VOID.panel[3], 0.95)

    local accent = frame.titleBar:CreateTexture(nil, 'ARTWORK')
    accent:SetPoint('BOTTOMLEFT', 0, 0)
    accent:SetPoint('BOTTOMRIGHT', 0, 0)
    accent:SetHeight(1)
    accent:SetColorTexture(VOID.bright[1], VOID.bright[2], VOID.bright[3], 0.75)

    frame.title = frame.titleBar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    frame.title:SetPoint('LEFT', 9, 0)
    frame.title:SetText('VOIDMARK  •  TAUNT')
    frame.title:SetTextColor(VOID.bright[1], VOID.bright[2], VOID.bright[3], 1)

    frame.close = CreateVoidButton(frame.titleBar, 22, 20, 'x')
    frame.close:SetPoint('RIGHT', -3, 0)
    frame.close:SetScript('OnClick', function() frame:Hide() end)

    frame.minimize = CreateVoidButton(frame.titleBar, 22, 20, '-')
    frame.minimize:SetPoint('RIGHT', frame.close, 'LEFT', -4, 0)
    frame.minimize:SetScript('OnClick', function()
        SetMinimized(not frame.minimized)
    end)

    -- Compact quick-select strip shown while minimized.
    frame.miniBar = CreateFrame('Frame', nil, frame)
    frame.miniBar:SetPoint('TOPLEFT', 1, -29)
    frame.miniBar:SetPoint('TOPRIGHT', -1, -29)
    frame.miniBar:SetHeight(28)

    local miniBg = frame.miniBar:CreateTexture(nil, 'BACKGROUND')
    miniBg:SetAllPoints()
    miniBg:SetColorTexture(VOID.panel[1], VOID.panel[2], VOID.panel[3], 0.92)

    frame.miniEmpty = frame.miniBar:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    frame.miniEmpty:SetPoint('CENTER', 0, 0)
    frame.miniEmpty:SetText('No saved quick phrases')
    frame.miniEmpty:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 1)

    frame.miniBar:Hide()

    frame.content = CreateFrame('Frame', nil, frame)
    frame.content:SetPoint('TOPLEFT', 1, -28)
    frame.content:SetPoint('BOTTOMRIGHT', -1, 1)

    frame.languageLabel = frame.content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    frame.languageLabel:SetPoint('TOPLEFT', 11, -10)
    frame.languageLabel:SetText('Lang')
    frame.languageLabel:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 1)

    frame.languageButton = CreateVoidButton(frame.content, 82, 22, 'Auto')
    frame.languageButton:SetPoint('LEFT', frame.languageLabel, 'RIGHT', 7, 0)
    frame.languageButton:SetScript('OnClick', CycleLanguageMode)
    frame.languageButton:SetScript('OnEnter', function(self)
        self._ttBackground:SetColorTexture(VOID.purple[1], VOID.purple[2], VOID.purple[3], 0.68)
        self.label:SetTextColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:SetText('Language')
        GameTooltip:AddLine('Click to cycle Auto / Orcish / Gutterspeak', 0.85, 0.75, 0.95)
        GameTooltip:Show()
    end)
    frame.languageButton:SetScript('OnLeave', function(self)
        self._ttBackground:SetColorTexture(VOID.panelSoft[1], VOID.panelSoft[2], VOID.panelSoft[3], VOID.panelSoft[4])
        self.label:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], VOID.text[4])
        GameTooltip:Hide()
    end)

    frame.input = CreateFrame('EditBox', nil, frame.content)
    frame.input:SetSize(190, 22)
    frame.input:SetPoint('LEFT', frame.languageButton, 'RIGHT', 7, 0)
    frame.input:SetAutoFocus(false)
    frame.input:SetMaxLetters(120)
    frame.input:SetFontObject(ChatFontNormal)
    frame.input:SetTextInsets(6, 6, 0, 0)
    frame.input:SetTextColor(VOID.text[1], VOID.text[2], VOID.text[3], 1)
    StylePanel(frame.input, VOID.panelSoft, { VOID.purple[1], VOID.purple[2], VOID.purple[3], 0.70 }, 1)
    frame.input:SetScript('OnEnterPressed', SavePhrase)
    frame.input:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)
    frame.input:SetScript('OnTextChanged', UpdatePreview)

    frame.save = CreateVoidButton(frame.content, 50, 22, 'Save')
    frame.save:SetPoint('LEFT', frame.input, 'RIGHT', 7, 0)
    frame.save:SetScript('OnClick', SavePhrase)

    frame.preview = frame.content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    frame.preview:SetPoint('TOPLEFT', 11, -39)
    frame.preview:SetPoint('TOPRIGHT', -11, -39)
    frame.preview:SetJustifyH('LEFT')
    frame.preview:SetWordWrap(false)
    frame.preview:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 1)
    frame.preview:SetText('Enemy sees: —')

    frame.savedLabel = frame.content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    frame.savedLabel:SetPoint('TOPLEFT', 11, -61)
    frame.savedLabel:SetText('Saved Phrases')
    frame.savedLabel:SetTextColor(VOID.bright[1], VOID.bright[2], VOID.bright[3], 1)

    frame.echoLabel = frame.content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    frame.echoLabel:SetPoint('TOPLEFT', 192, -61)
    frame.echoLabel:SetText('Echo Sees')
    frame.echoLabel:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 1)

    frame.echoParty = CreateVoidButton(frame.content, 70, 20, '[ ] Party')
    frame.echoParty:SetPoint('LEFT', frame.echoLabel, 'RIGHT', 6, 0)
    frame.echoParty:SetScript('OnClick', ToggleEchoParty)

    frame.echoSay = CreateVoidButton(frame.content, 58, 20, '[ ] Say')
    frame.echoSay:SetPoint('LEFT', frame.echoParty, 'RIGHT', 5, 0)
    frame.echoSay:SetScript('OnClick', ToggleEchoSay)

    frame.scroll = CreateFrame('ScrollFrame', nil, frame.content)
    frame.scroll:SetPoint('TOPLEFT', 10, -80)
    frame.scroll:SetPoint('TOPRIGHT', -10, -80)
    frame.scroll:SetHeight(VISIBLE_ROWS * ROW_HEIGHT)
    frame.scroll:EnableMouseWheel(true)

    frame.scrollChild = CreateFrame('Frame', nil, frame.scroll)
    frame.scrollChild:SetWidth(370)
    frame.scrollChild:SetHeight(1)
    frame.scroll:SetScrollChild(frame.scrollChild)

    frame.scroll:SetScript('OnMouseWheel', function(self, delta)
        local total = frame.scrollChild:GetHeight() or 0
        local visible = self:GetHeight() or 0
        local maxScroll = math.max(0, total - visible)
        local current = self:GetVerticalScroll() or 0
        local nextScroll = current - (delta * ROW_HEIGHT * 2)
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > maxScroll then nextScroll = maxScroll end
        self:SetVerticalScroll(nextScroll)
    end)

    frame.footer = frame.content:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    frame.footer:SetPoint('BOTTOM', 0, 7)
    frame.footer:SetText('Click = YELL  •  Shift-click = SAY  •  Echo = readable original')
    frame.footer:SetTextColor(VOID.muted[1], VOID.muted[2], VOID.muted[3], 0.85)

    frame:SetScript('OnShow', function()
        EnsureDB()
        RefreshLanguageButton()
        RefreshEchoButtons()
        RefreshRows()
        UpdatePreview()
        SetMinimized(TaliaaTauntDB.minimized == true)
    end)


    RestoreFramePosition(frame, 'windowPosition', 'CENTER', 0, 0)
    frame:Hide()
    return frame
end

local function ToggleFrame()
    local f = CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

-- VoidMark module API. Keeps the existing slash commands while allowing the
-- VoidMark gear menu to open the integrated tool directly.
_G.VoidMarkTaunt = _G.VoidMarkTaunt or {}
VoidMarkTaunt.Toggle = ToggleFrame
VoidMarkTaunt.Show = function() local f = CreateMainFrame(); f:Show() end
VoidMarkTaunt.Hide = function() if frame then frame:Hide() end end

local loader = CreateFrame('Frame')
VoidMarkForever.RegisterEvent(loader,'ADDON_LOADED')
loader:SetScript('OnEvent', function(self, event, loadedName)
    if loadedName ~= addonName then return end
    EnsureDB()
    self:UnregisterEvent('ADDON_LOADED')
end)

SLASH_TALIAATAUNT1 = '/ttaunt'
SLASH_TALIAATAUNT2 = '/taliaataunt'
SlashCmdList.TALIAATAUNT = function()
    ToggleFrame()
end

SLASH_TALIAATAUNT_SAY1 = '/ts'
SlashCmdList.TALIAATAUNT_SAY = function(msg)
    SendTranslated(msg, 'SAY')
end

SLASH_TALIAATAUNT_YELL1 = '/ty'
SlashCmdList.TALIAATAUNT_YELL = function(msg)
    SendTranslated(msg, 'YELL')
end
