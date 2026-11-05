local VMAPI = VoidMarkForever.API
local _, A = ...
local function text(parent,size)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    t:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size or 11); t:SetJustifyH("LEFT"); return t
end
local function button(parent,label,x,y,w,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetSize(w or 80,22); b:SetPoint("TOPLEFT",x,y); b:SetText(label); b:SetScript("OnClick",fn); return b
end
local function shortGY(name)
    if not name or name=="" then return "Unknown" end
    if name=="Stranglethorn Vale, Northern Stranglethorn" then return "Northern STV" end
    if name=="Stranglethorn Vale, Booty Bay" then return "Booty Bay" end
    return name:match(",%s*(.+)$") or name
end
function A:ApplyAppearance()
    if not self.frame then return end
    local s=self.db.settings; self.frame:SetAlpha(s.alpha); self.frame:SetScale(s.scale)
    self.frame:SetShown(not s.hidden)
end
function A:CreateUI()
    local f=CreateFrame("Frame","TaliaaRunBackFrame",UIParent,"BackdropTemplate"); self.frame=f; self.rows={}; self.page=1
    f:SetSize(540,90); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    f:SetBackdropColor(.055,.045,.075,.95); f:SetBackdropBorderColor(.35,.26,.46,1)
    local pos=self.char.position
    if type(pos)=="table" and type(pos.x)=="number" and type(pos.y)=="number" then f:SetPoint(pos.point or "CENTER",UIParent,pos.relativePoint or "CENTER",pos.x,pos.y) else f:SetPoint("CENTER",UIParent,"CENTER",0,120) end
    f:SetScript("OnDragStart",function() if not A.db.settings.locked then f:StartMoving() end end)
    f:SetScript("OnDragStop",function()
        f:StopMovingOrSizing(); local point,_,relativePoint,x,y=f:GetPoint()
        A.char.position={point=point,relativePoint=relativePoint,x=x,y=y}
    end)
    self.title=text(f,11); self.title:SetPoint("TOPLEFT",10,-9); self.title:SetText("EARLIEST POSSIBLE RETURN")
    button(f,"<",406,-3,24,function() A.page=math.max(1,A.page-1); A:RenderRows() end)
    button(f,">",432,-3,24,function() A.page=A.page+1; A:RenderRows() end)
    button(f,"...",460,-3,32,function() A:ShowSettings() end)
    button(f,"x",498,-3,30,function() A.db.settings.hidden=true; A:ApplyAppearance() end)
    self.footer=text(f,9); self.footer:SetTextColor(.7,.65,.8); self.footer:SetPoint("BOTTOMLEFT",10,7)
    for i=1,20 do
        local row=CreateFrame("Button",nil,f); row:SetPoint("TOPLEFT",8,-29-(i-1)*24); row:SetSize(524,23)
        row.name=text(row,11); row.name:SetPoint("LEFT",3,0); row.name:SetWidth(145)
        row.gy=text(row,10); row.gy:SetPoint("LEFT",153,0); row.gy:SetWidth(196); row.gy:SetTextColor(.75,.72,.82)
        row.timer=text(row,10); row.timer:SetPoint("RIGHT",-3,0); row.timer:SetJustifyH("RIGHT"); row.timer:SetWidth(171)
        row:SetScript("OnEnter",function()
            if not row.record then return end
            GameTooltip:SetOwner(row,"ANCHOR_RIGHT"); GameTooltip:AddLine(row.record.name,1,1,1)
            for _,line in ipairs(A:DetailLines(row.record)) do GameTooltip:AddLine(line,.8,.8,.85,true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row:SetScript("OnClick",function(_,mouse)
            if not row.record then return end
            if mouse=="RightButton" then A.active[row.record.guid]=nil; A:RenderRows(); A:Save(); A:ArmTimer()
            else A:ShowReport("Enemy details",table.concat(A:DetailLines(row.record),"\n")) end
        end)
        self.rows[i]=row
    end
    self:ApplyAppearance()
end
function A:DetailLines(r)
    local c=r.calc or {}; local p=r.position
    return {
        r.name.." | level "..tostring(r.level or "?").." | "..tostring(r.class or "?").." | "..tostring(r.race or "?").." | "..tostring(r.faction),
        "Observer zone (death vicinity): "..tostring(r.zoneName or self:AreaName(r.zone)).." / "..tostring(r.subzone or "unknown").."; enemy area "..(r.exactArea and "known (test)" or "not exposed"),
        "Location: "..tostring(p and p.source or "unavailable"),
        p and string.format("World %s: %.2f, %.2f; uncertainty %s",tostring(p.map),p.x,p.y,p.uncertainty and (p.uncertainty.." yd") or "UNBOUNDED") or "No world coordinates",
        "Predicted graveyard: "..tostring(r.graveyardName).." ["..tostring(r.graveyard or "?").."]",
        "Countdown graveyard: "..tostring(r.warningGraveyardName or "unknown").." ["..tostring(r.warningGraveyard or c.floorGY or "?").."]",
        "Selection: "..tostring(r.selection),
        "Candidate scope: "..tostring(r.candidateScope or "legacy timer / unknown"),
        "Assignment source: "..tostring(r.assignmentSource),
        "Floor distance: "..(c.distance and string.format("%.1f yd",c.distance) or "unknown"),
        "Route estimate: "..(r.networkDistance and string.format("%.1f yd",r.networkDistance) or "unavailable").."; "..tostring(r.routeStatus),
        "Route ETA: "..(r.routeSeconds and string.format("~%d:%02d from death",math.floor(r.routeSeconds/60),math.floor(r.routeSeconds)%60) or "unavailable").." (advisory; never delays EARLIEST warning)",
        "Calibration: "..tostring(r.calibrationNote or "none for this route"),
        "Ghost speed: "..tostring(c.speed).." yd/s; "..tostring(c.speedReason),
        "Reclaim radius: "..tostring(c.radius).." yd (early-warning allowance); added delay: "..tostring(c.delay).." s",
        "Uncertainty: "..tostring(c.adjustment),
        "Confidence: "..tostring(c.confidence).."; "..tostring(c.reason),
        "Status: "..self:TimerLabel(r).." | Corpse run only; self/other resurrection can occur earlier.",
        "Enemy sightings never change or train this estimate.",
    }
end
function A:RenderRows()
    if not self.frame then return end
    local list={}; for _,r in pairs(self.active) do list[#list+1]=r end
    table.sort(list,function(a,b) if a.diedAt==b.diedAt then return a.guid<b.guid end return a.diedAt>b.diedAt end)
    local count=self.db.settings.rows; local pages=math.max(1,math.ceil(#list/count)); self.page=math.min(self.page,pages)
    for i,row in ipairs(self.rows) do
        local r=i<=count and list[(self.page-1)*count+i] or nil; row.record=r; row:SetShown(r~=nil)
        if r then
            row.name:SetText((r.test and "[TEST] " or "")..r.name)
            local gy=shortGY(r.warningGraveyardName or r.graveyardName or "Unknown")
            row.gy:SetText(gy..(r.calc.confidence=="UNKNOWN" and " | ?" or " | LOW"))
            row.timer:SetText(self:TimerLabel(r)); if r.readyAt<=self:Now() then row.timer:SetTextColor(1,.55,.3) else row.timer:SetTextColor(.8,.7,1) end
        end
    end
    local visible=math.min(count,math.max(0,#list-(self.page-1)*count))
    self.frame:SetHeight(54+math.max(1,visible)*24)
    self.footer:SetText(#list==0 and "No tracked deaths. /trb test | drag header to move" or string.format("%d tracked | page %d/%d | LOW = optimistic floor; ? = unknown | right-click removes",#list,self.page,pages))
end
function A:ShowReport(title,body)
    if not self.report then
        local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate"); self.report=f
        f:SetSize(700,480); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
        f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); f:SetBackdropColor(.06,.05,.08,1)
        f.title=text(f,14); f.title:SetPoint("TOPLEFT",15,-12)
        button(f,"Close",610,-7,75,function() f:Hide() end)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",15,-44); scroll:SetPoint("BOTTOMRIGHT",-35,18)
        local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(645)
        edit:SetScript("OnEscapePressed",function() edit:ClearFocus() end); scroll:SetScrollChild(edit); f.edit=edit
    end
    local lines=0; for line in (body.."\n"):gmatch("(.-)\n") do lines=lines+math.max(1,math.ceil(#line/75)) end
    self.report.edit:SetHeight(math.max(420,lines*16+40))
    self.report.title:SetText(title); self.report.edit:SetText(body); self.report.edit:SetCursorPosition(0); self.report:Show()
end
function A:ShowSettings()
    if not self.frame then
        self:ShowReport("VoidMark runback settings",table.concat({
            "Timers appear in the normal VoidMark rows. Use VoidMark settings for their appearance.",
            "Route diagnostics for details/calibration: "..tostring(self.db.settings.routes),
            "/trb routes on | off - enable routes for requested details and own-player calibration",
            "/trb details [name] - inspect an active timer",
            "/trb route [name] - explicitly calculate its advisory route",
            "/trb test [normal|nightelf] - create a local test row",
            "/trb calibrate - measure your own corpse run; release immediately",
            "/trb calibrate report | cancel | clear",
            "/trb clear - remove transient timers",
            "Route estimates and calibration never postpone the visible countdown.",
        },"\n"))
        return
    end
    if self.settingsFrame then self.settingsFrame:Show(); return end
    local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate"); self.settingsFrame=f
    f:SetSize(370,270); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); f:SetBackdropColor(.07,.05,.1,1)
    local title=text(f,14); title:SetPoint("TOPLEFT",14,-12); title:SetText("Taliaa Run Back settings")
    button(f,"Close",278,-6,80,function() f:Hide() end)
    local status=text(f,11); status:SetPoint("TOPLEFT",15,-50)
    local function refresh()
        local s=A.db.settings; status:SetText(string.format("Opacity %.2f  |  Scale %.2f  |  Rows %d\nLocked: %s  |  Route diagnostics: %s",s.alpha,s.scale,s.rows,tostring(s.locked),tostring(s.routes)))
        A:ApplyAppearance(); A:RenderRows()
    end
    button(f,"Opacity -",15,-100,100,function() A.db.settings.alpha=math.max(.15,A.db.settings.alpha-.1); refresh() end)
    button(f,"Opacity +",125,-100,100,function() A.db.settings.alpha=math.min(1,A.db.settings.alpha+.1); refresh() end)
    button(f,"Scale -",15,-130,100,function() A.db.settings.scale=math.max(.6,A.db.settings.scale-.1); refresh() end)
    button(f,"Scale +",125,-130,100,function() A.db.settings.scale=math.min(2,A.db.settings.scale+.1); refresh() end)
    button(f,"Rows -",15,-160,100,function() A.db.settings.rows=math.max(1,A.db.settings.rows-1); refresh() end)
    button(f,"Rows +",125,-160,100,function() A.db.settings.rows=math.min(20,A.db.settings.rows+1); refresh() end)
    button(f,"Lock / unlock",15,-190,130,function() A.db.settings.locked=not A.db.settings.locked; refresh() end)
    button(f,"Route details on/off",155,-190,190,function() A.db.settings.routes=not A.db.settings.routes; refresh() end)
    button(f,"Test",15,-225,100,function() A:TestDeath(); refresh() end)
    button(f,"Clear timers",125,-225,100,function() A:ClearTimers(); refresh() end)
    refresh()
end
