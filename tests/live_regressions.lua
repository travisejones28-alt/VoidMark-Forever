-- Live port: visible combat rows preserve full identities and remain nonsecure.
local oldList=VoidMark.db.profile.CurrentList
VoidMark.db.profile.CurrentList=1
VoidMark.MainWindow:Show()
TEST_IN_COMBAT=true
VoidMark:QueueCombatSighting('Live-One','test')
VoidMark:QueueCombatSighting('Live-Two','test')
local overlay=VoidMark.CombatNearbyRows
assert(overlay and overlay:IsShown())
assert(overlay:GetFrameStrata()=='LOW','Combat rows cover stock windows')
local names={}
for _,row in ipairs(overlay.Rows) do
    if row:IsShown() then names[row.Name:GetText()]=true end
    assert(not next(row.attributes),'Visual row gained secure target attributes')
end
assert(names['Live One'] and names['Live Two'],'Combat names lost their secondary identity')
NOW=NOW+31
VoidMark:UpdateCombatQueueBar()
assert(not overlay:IsShown(),'Expired sightings remain visible')
VoidMark:QueueCombatSighting('Live-Three','test')
VoidMark.MainWindow:Hide()
VoidMark:UpdateCombatQueueBar()
assert(not overlay:IsShown(),'Combat rows remain over a hidden main window')
TEST_IN_COMBAT=false
VoidMark:ClearCombatSightings()
VoidMark.db.profile.CurrentList=oldList

-- An accepted kill recovers a missing timer without replacing a good one.
local rb=VoidMarkRunBack
local outdoor,capture,create=rb.IsOutdoor,rb.CaptureLocation,rb.CreateTimer
rb.IsOutdoor=function()return true end
rb.CaptureLocation=function()return nil,nil,nil end
local created=0
rb.CreateTimer=function(self,r) created=created+1; self.active[r.guid]=r end
local guid='Player-1-livefallback'
rb.active[guid]=nil; rb.lastDeath[guid]=nil
VoidMark:EnsureRunBackForConfirmedKill('Fallback-One',guid)
VoidMark:EnsureRunBackForConfirmedKill('Fallback-One',guid)
assert(created==1,'RunBack fallback duplicated or missed timer')
assert(rb.active[guid].faction=='Alliance','Fallback faction is incorrect')
rb.active[guid]=nil; rb.lastDeath[guid]=nil
rb.IsOutdoor,rb.CaptureLocation,rb.CreateTimer=outdoor,capture,create
local getRecord=VoidMark.GetRunBackRecord
VoidMark.GetRunBackRecord=function()return {readyAt=NOW-20,calc={confidence='UNKNOWN'}} end
assert(VoidMark:GetRunBackDisplay('Fallback-One').time=='GY ?','Unknown position claims immediate return')
VoidMark.GetRunBackRecord=getRecord
print('PASS: live combat rows, full names, expiry, hidden window and RunBack fallback')
