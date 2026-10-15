-- WHO-based KOS zone sightings. Keep complete Forever character identities.
local F=VoidMarkForever
local prefix="VMKOS1"
local f=CreateFrame("Frame")
local alerts,shares={},{}
local db
local banner=CreateFrame("Frame","VoidMarkKOSWhoBanner",UIParent)
banner:SetSize(460,65)
banner:SetPoint("TOP",0,-150)
banner:SetFrameStrata("HIGH")
local label=banner:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
label:SetAllPoints()
banner.Text=label
banner:Hide()
local token=0
local visibleNames={}
local visibleKeys={}
local bannerExpires=0

local function Init()
    if not VoidMarkDB then return end
    VoidMarkDB.VoidMarkKOSWho=VoidMarkDB.VoidMarkKOSWho or {}
    db=VoidMarkDB.VoidMarkKOSWho
    if db.enabled==nil then db.enabled=true end
    if db.sound==nil then db.sound=true end
    if db.share==nil then db.share=true end
    if db.shareReasons==nil then db.shareReasons=false end
    if db.cooldown==nil then db.cooldown=180 end
end

local function Clean(s,n)
    s=F.Readable(s)
    if type(s)~="string" and type(s)~="number" then return "" end
    return tostring(s):gsub("[%c|]"," "):sub(1,n or 80)
end
local function Key(name)
    return Clean(name,130):gsub("%s+","-"):lower()
end

local function FindKOS(name)
    if not VoidMarkPerCharDB or type(VoidMarkPerCharDB.KOSData)~="table" then return nil end
    local target=Key(name)
    if target=="" then return nil end
    for stored,added in pairs(VoidMarkPerCharDB.KOSData) do
        if added and Key(stored)==target then
            return VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[stored] or {}
        end
    end
end

local function Reason(data)
    if type(data)~="table" or type(data.reason)~="table" then return "" end
    for why,extra in pairs(data.reason) do
        if extra and extra~=false then
            if type(extra)=="string" and extra~="" then return Clean(extra,80) end
            return Clean(why,80)
        end
    end
    return ""
end

local function Notify(owner,name,level,class,zone,reason)
    if not db or not db.enabled then return end
    local key=Key(owner)..":"..Key(name)..":"..zone:lower()
    local now=GetTime()
    if alerts[key] and now-alerts[key]<(tonumber(db.cooldown) or 180) then return end
    alerts[key]=now
    local who=owner=="You" and "YOUR KOS" or (F.DisplayName(owner).."'s KOS")
    local msg="|cffff5555[VoidMark KOS]|r "..who..": "..Clean(F.DisplayName(name),65)
        .." Lv"..tostring(level or "?").." "..Clean(class,24).." in "..Clean(zone,70)
    if reason and reason~="" then msg=msg.." | Reason: "..Clean(reason,80) end
    DEFAULT_CHAT_FRAME:AddMessage(msg)
    -- Keep all alerts in the same 10-second display window, separated by commas.
    -- A distinct owner/name pair is displayed once, even if several WHO packets arrive.
    if now >= bannerExpires then
        visibleNames={}
        visibleKeys={}
    end
    local displayKey=Key(who)..":"..Key(name)
    if not visibleKeys[displayKey] then
        visibleKeys[displayKey]=true
        visibleNames[#visibleNames+1]=who..": "..Clean(F.DisplayName(name),65)..((class and tostring(class)~="") and (" ("..Clean(class,24)..")") or "")
    end
    bannerExpires=now+10
    token=token+1
    local current=token
    label:SetText("|cffff5555KOS DETECTED|r\n"..table.concat(visibleNames,", "))
    banner:Show()
    C_Timer.After(10,function()
        if token==current then
            banner:Hide()
            visibleNames={}
            visibleKeys={}
        end
    end)
    if db.sound and PlaySound then
        pcall(PlaySound,SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,"Master")
    end
end

local function SendMatch(name,level,class,zone,reason)
    if not db.share then return end
    local channel=F.Safe(IsInRaid) and "RAID" or (F.Safe(IsInGroup) and "PARTY" or nil)
    if not channel then return end
    local key=Key(name)..":"..zone:lower()
    local now=GetTime()
    if shares[key] and now-shares[key]<(tonumber(db.cooldown) or 180) then return end
    shares[key]=now
    local send=C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
    if type(send)~="function" then return end
    pcall(send,prefix,table.concat({"K",Clean(name,65),tostring(level or ""),
        Clean(class,24),Clean(zone,70),db.shareReasons and Clean(reason,80) or ""},"\031"),channel)
end

local function ReceiveWho(name,level,class,zone,privateRequest)
    if not db then Init() end
    if not db or not db.enabled then return end
    name=Clean(name,65)
    level=F.Readable(level)
    class=Clean(class,24)
    zone=Clean(zone,70)
    if name=="" or zone=="" then return end
    local data=FindKOS(name)
    if not data then return end
    local reason=Reason(data)
    Notify("You",name,level,class,zone,reason)
    if not privateRequest then SendMatch(name,level,class,zone,reason) end
end
_G.VoidMarkKOS_OnWhoResult=ReceiveWho

local function IsSelf(sender)
    local name=F.FullName("player")
    return type(sender)=="string" and name and Key(sender)==Key(name)
end

local function InOurGroup(sender)
    return F.Safe(IsInGroup)==true and (IsSelf(sender) or F.IsGroupSender(sender))
end

F.RegisterEvent(f,"PLAYER_LOGIN")
F.RegisterEvent(f,"CHAT_MSG_ADDON")
f:SetScript("OnEvent",function(_,event,p,m,channel,sender)
    if event=="PLAYER_LOGIN" then
        Init()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            F.Safe(C_ChatInfo.RegisterAddonMessagePrefix,prefix)
        end
        return
    end
    p=F.Readable(p); m=F.Readable(m)
    channel=F.Readable(channel); sender=F.Readable(sender)
    if p~=prefix or type(m)~="string" or type(sender)~="string" or #m>255 then return end
    local groupMessage=(channel=="PARTY" or channel=="RAID") and InOurGroup(sender)
    local guildWhisper=channel=="WHISPER" and F.Safe(IsInGuild)==true
    if not groupMessage and not guildWhisper then return end
    local fields={}
    for part in (m.."\031"):gmatch("(.-)\031") do
        fields[#fields+1]=part
        if #fields==6 then break end
    end
    if fields[1]=="G" and guildWhisper then
        -- Requested WHO roster: only this recipient checks their private KOS
        -- list. Do not rebroadcast matches to their party.
        ReceiveWho(fields[3],tonumber(fields[4]),fields[5],fields[2],true)
    elseif fields[1]=="W" and groupMessage then
        ReceiveWho(fields[3],tonumber(fields[4]),fields[5],fields[2])
    elseif fields[1]=="K" and groupMessage and fields[2] and fields[5] then
        -- Don't echo our own party-share message as a second alert.
        if not IsSelf(sender) then
            Notify(sender,fields[2],tonumber(fields[3]),fields[4],fields[5],fields[6])
        end
    end
end)

SLASH_VOIDMARKWHO1="/vmkos"
SlashCmdList.VOIDMARKWHO=function(msg)
    if not db then Init() end
    if not db then return end
    local cmd,value=tostring(msg or ""):lower():match("^(%S+)%s*(%S*)")
    if cmd=="on" or cmd=="off" then db.enabled=cmd=="on"
    elseif cmd=="share" then db.share=value=="on"
    elseif cmd=="reasons" then db.shareReasons=value=="on"
    elseif cmd=="sound" then db.sound=value=="on"
    elseif cmd=="cooldown" then db.cooldown=math.max(30,math.min(1800,tonumber(value) or 180))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffb56cffVoidMark KOS WHO|r enabled="..tostring(db.enabled)
        .." sharing="..tostring(db.share).." reasons="..tostring(db.shareReasons)
        .." sound="..tostring(db.sound).." cooldown="..tostring(db.cooldown).."s")
end
