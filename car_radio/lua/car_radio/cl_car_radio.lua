-- cl_car_radio.lua — UNLOCK global fiable + volume non-0 au démarrage + initiateur-only popup
if not CLIENT then return end

if istable(CAR_RADIO) and CAR_RADIO.__core_loaded then return end

CAR_RADIO = CAR_RADIO or {}
CAR_RADIO.__core_loaded = true

-- [vehIdx] = { veh, url, started, gain=1, panel?, radius, falloff, lastVol, lastSeenInRangeAt }
local Radios = Radios or {}

-- Déverrouillage audio (CE client, pour toute la session)
local AudioUnlockedGlobal = false
local GlobalUnlockUI      = nil    -- barre "Activer l'audio"
local GlobalUnlockDHTML   = nil    -- DHTML gardé vivant après unlock
local GlobalClickerWasOn  = false

-- Helpers convars
local function radius()  return GetConVar("car_radio_radius"):GetFloat() end
local function falloff() return math.max(0.2, GetConVar("car_radio_falloff"):GetFloat()) end

-- exposé HUD
function CAR_RADIO_GetVehicleGain(veh)
    if not IsValid(veh) then return 1 end
    local R = Radios[veh:EntIndex()]
    return math.Clamp((R and R.gain) or 1, 0, 1)
end

-- JS safe quote
local function js_quote(s)
    s = tostring(s or "")
    local json = util.TableToJSON({ s })
    local quoted = json and json:match("^%[(.*)%]$")
    if not quoted then
        s = s:gsub("\\","\\\\"):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t"):gsub("\"","\\\"")
        quoted = "\"" .. s .. "\""
    end
    return quoted
end

-- Page HTML avec gestion "pending volume" (appliqué même si appelé avant onReady)
local function HtmlPage()
    return [[
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#000;overflow:hidden}
#wrap{position:relative;width:320px;height:180px}
#p{width:100%;height:100%}
#unlockBtn{position:absolute;left:0;top:0;width:100%;height:100%;opacity:0;z-index:9999;cursor:pointer;border:0;background:transparent}
</style>
<script>
var s=document.createElement('script'); s.src="https://www.youtube.com/iframe_api"; (document.head||document.documentElement).appendChild(s);
var player, ready=false, firstClickDone=false;
var pendingVol=30;  // volume stocké, appliqué dès que possible

function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{
    host:'https://www.youtube-nocookie.com',
    videoId:'',
    events:{'onReady':function(){
      ready=true;
      try{ player.setVolume(pendingVol); if(pendingVol>0) player.unMute(); }catch(e){}
    }},
    playerVars:{autoplay:1,controls:1,disablekb:0,fs:0,modestbranding:1,iv_load_policy:3,rel:0,playsinline:1,origin:'https://www.youtube.com'}
  });
}

function extractID(u){
  try{
    if(!u) return null;
    var i=u.indexOf("v="); if(i>=0){ var id=u.substring(i+2); var c=id.indexOf("&"); if(c>=0) id=id.substring(0,c); c=id.indexOf("#"); if(c>=0) id=id.substring(0,c); return id; }
    var j=u.indexOf("youtu.be/"); if(j>=0){ var id2=u.substring(j+9); var stop=-1; var q=id2.indexOf("?"); if(q>=0) stop=(stop<0?q:Math.min(stop,q)); var a=id2.indexOf("&"); if(a>=0) stop=(stop<0?a:Math.min(stop,a)); var h=id2.indexOf("#"); if(h>=0) stop=(stop<0?h:Math.min(stop,h)); if(stop>=0) id2=id2.substring(0,stop); return id2; }
  }catch(e){}
  return null;
}

function setUrl(u){
  try{
    var id=extractID(u);
    if(id){
      if(ready){ player.loadVideoById(id); }
      else { // charge à la 1ère readiness
        var _id = id;
        var i = setInterval(function(){
          if(ready){ clearInterval(i); try{ player.loadVideoById(_id); }catch(e){} }
        }, 100);
      }
    }
  }catch(e){}
}

function seekPlay(sec){
  try{
    var s = Math.max(0,parseInt(sec||0,10));
    if(ready){ player.seekTo(s,true); player.playVideo(); }
    else {
      var i = setInterval(function(){
        if(ready){ clearInterval(i); try{ player.seekTo(s,true); player.playVideo(); }catch(e){} }
      }, 100);
    }
  }catch(e){}
}

function setVol(v){
  try{
    var vv=Math.max(0,Math.min(100,parseInt(v||0,10)));
    pendingVol = vv;
    if(!ready) return;
    if(vv<=0){ player.mute(); } else { player.unMute(); player.setVolume(vv); }
  }catch(e){}
}

function wake(){
  try{
    if(ready){ player.playVideo(); if(pendingVol>0) player.unMute(); player.setVolume(pendingVol); }
  }catch(e){}
}

function stop(){ try{ if(ready){ player.stopVideo(); } }catch(e){} }

function firstUserClick(){ if(firstClickDone) return; firstClickDone=true;
  try{ pendingVol = Math.max(25,pendingVol); }catch(e){}
  try{ if(ready){ player.playVideo(); player.unMute(); player.setVolume(pendingVol); } }catch(e){}
  try{ var b=document.getElementById('unlockBtn'); if(b) b.style.display='none'; }catch(e){}
  try{ if(window.gmod && gmod.Interact){ gmod.Interact(); } }catch(e){}
}

window.addEventListener('DOMContentLoaded',function(){
  var b=document.getElementById('unlockBtn'); if(b){ b.addEventListener('click',firstUserClick,{passive:true}); }
});
</script></head><body><div id="wrap"><div id="p"></div><button id="unlockBtn"></button></div></body></html>
]]
end

-- Conteneur caché (rendu hors-écran)
local function CreateHiddenContainer()
    local pnl = vgui.Create("DPanel")
    pnl:SetSize(256, 256)
    pnl:SetPos(ScrW() + 200, 50)
    pnl:SetVisible(true)
    pnl:SetMouseInputEnabled(false)
    pnl:SetKeyboardInputEnabled(false)
    return pnl
end

-- Réveille tous les lecteurs existants après unlock global
local function NudgeAllPlayersAfterUnlock()
    for _, R in pairs(Radios) do
        if IsValid(R.panel) then
            -- wake() + petit volume pour sortir du mute ; Think recalcule le vrai volume ensuite
            R.panel:QueueJavascript("try{ wake(); setVol(30); }catch(e){}")
            R.lastVol = nil
        end
    end
end

----------------------------------------------------------------------
-- UNLOCK GLOBAL (barre + mini-popup DHTML)
----------------------------------------------------------------------

local function RemoveGlobalUnlockUI()
    if IsValid(GlobalUnlockUI) then GlobalUnlockUI:Remove() end
    GlobalUnlockUI = nil
    if not GlobalClickerWasOn then
        gui.EnableScreenClicker(false)
    end
end

local function OpenMiniUnlockPopup(onUnlocked)
    -- Mini popup 200x120 : l’utilisateur clique DANS la webview
    local fm = vgui.Create("DFrame")
    fm:SetTitle("Activer l'audio (1 clic)")
    fm:SetSize(200, 120)
    fm:Center()
    fm:MakePopup()
    fm:SetSizable(false)
    fm:SetDeleteOnClose(true)

    local lbl = vgui.Create("DLabel", fm)
    lbl:Dock(TOP); lbl:DockMargin(8,6,8,4)
    lbl:SetText("Clique dans la zone noire ↓")
    lbl:SetTextColor(Color(230,230,230))

    local dhtml = vgui.Create("DHTML", fm)
    dhtml:Dock(FILL); dhtml:DockMargin(8,4,8,8)
    dhtml:SetHTML(HtmlPage())

    dhtml:AddFunction("gmod","Interact", function()
        timer.Simple(0.1, function()
            if not IsValid(dhtml) then return end
            local hidden = CreateHiddenContainer()
            dhtml:SetParent(hidden)
            dhtml:SetSize(hidden:GetWide(), hidden:GetTall())
            dhtml:SetPos(0,0)

            AudioUnlockedGlobal = true
            GlobalUnlockDHTML = dhtml -- garde en vie
            if onUnlocked then onUnlocked() end

            -- Réveille les lecteurs déjà présents
            NudgeAllPlayersAfterUnlock()

            if IsValid(fm) then fm:Close() end
            chat.AddText(Color(120,200,255), "[CarRadio] ", color_white, "Audio activé pour cette session.")
        end)
    end)

    function dhtml:OnDocumentReady(_)
        -- On lance une vidéo et on met un volume ~30 de base (si autorisé)
        self:QueueJavascript("try{ setUrl('https://youtu.be/dQw4w9WgXcQ'); setVol(30); seekPlay(0); }catch(e){}")
    end
end

local function EnsureGlobalUnlockUI()
    if AudioUnlockedGlobal or IsValid(GlobalUnlockUI) then return end

    GlobalClickerWasOn = vgui.CursorVisible()
    if not GlobalClickerWasOn then gui.EnableScreenClicker(true) end

    local fr = vgui.Create("DPanel")
    GlobalUnlockUI = fr
    fr:SetSize(360, 40)
    fr:SetPos(ScrW() - fr:GetWide() - 16, 16)
    fr:SetZPos(10000)
    fr:SetMouseInputEnabled(true)
    fr:SetKeyboardInputEnabled(false)

    function fr:Paint(w,h)
        surface.SetDrawColor(10,12,16,235); surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(120,200,255,170); surface.DrawOutlinedRect(0,0,w,h,2)
        draw.SimpleText("Activer l'audio des radios (1 clic)", "Trebuchet18", 10, h/2, Color(220,230,255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btn = vgui.Create("DButton", fr)
    btn:SetText("Activer")
    btn:SetWide(96); btn:SetTall(26)
    btn:SetPos(fr:GetWide()-btn:GetWide()-8, (fr:GetTall()-btn:GetTall())/2)
    btn:SetMouseInputEnabled(true)
    btn.DoClick = function()
        OpenMiniUnlockPopup(function() RemoveGlobalUnlockUI() end)
    end
end

-- Commande pour afficher la barre si besoin
concommand.Add("car_radio_unlock", function()
    if AudioUnlockedGlobal then
        chat.AddText(Color(120,200,255), "[CarRadio] ", color_white, "Audio déjà activé pour cette session.")
        return
    end
    EnsureGlobalUnlockUI()
    chat.AddText(Color(120,200,255), "[CarRadio] ",
        color_white, "Clique sur ", Color(255,255,0), "Activer", color_white, " (barre en haut à droite) pour débloquer l'audio (1 fois).")
end)

----------------------------------------------------------------------
-- POPUP 1-CLIC (INITIATEUR SEULEMENT)
----------------------------------------------------------------------

local BootstrapCtx = nil
local function CloseBootstrap()
    if BootstrapCtx then
        if IsValid(BootstrapCtx.frame) then BootstrapCtx.frame:Close() end
        BootstrapCtx = nil
    end
end

local function EnsureAudioUnlockedForInitiator(vehIdx, url, seekSeconds, onReadyWithPanel)
    if BootstrapCtx and BootstrapCtx.vehIdx ~= vehIdx then CloseBootstrap() end
    if BootstrapCtx then return end

    local frm = vgui.Create("DFrame")
    frm:SetTitle("Car Radio — Activer l'audio (1 clic)")
    frm:SetSize(360, 260)
    frm:Center()
    frm:MakePopup()

    local lbl = vgui.Create("DLabel", frm)
    lbl:Dock(TOP); lbl:DockMargin(10,8,10,6)
    lbl:SetText("Clique une fois dans la vidéo pour activer le son (YouTube).")
    lbl:SetTextColor(Color(230,230,230))

    local dhtml = vgui.Create("DHTML", frm)
    dhtml:Dock(FILL); dhtml:DockMargin(10,4,10,10)
    dhtml:SetHTML(HtmlPage())

    BootstrapCtx = { frame = frm, dhtml = dhtml, vehIdx = vehIdx }

    dhtml:AddFunction("gmod","Interact", function()
        local qurl = js_quote(url or "")
        dhtml:QueueJavascript(("try{ setUrl(%s); }catch(e){}"):format(qurl))
        dhtml:QueueJavascript(("try{ seekPlay(%d); setVol(40); }catch(e){}"):format(math.max(0, math.floor(seekSeconds or 0))))

        -- 🔹 ferme automatiquement après 1 seconde
        timer.Simple(1, function()
            if not IsValid(frm) or not IsValid(dhtml) then return end
            local hidden = CreateHiddenContainer()
            dhtml:SetParent(hidden)
            dhtml:SetSize(hidden:GetWide(), hidden:GetTall())
            dhtml:SetPos(0, 0)
            if onReadyWithPanel then onReadyWithPanel(dhtml) end
            if IsValid(frm) then frm:Close() end
            BootstrapCtx = nil
        end)
    end)

    function dhtml:OnDocumentReady(_)
        local qurl = js_quote(url or "")
        self:QueueJavascript(("try{ setUrl(%s); setVol(35); }catch(e){}"):format(qurl))
    end

    function frm:OnClose()
        if BootstrapCtx and BootstrapCtx.frame == self then BootstrapCtx = nil end
    end
end


----------------------------------------------------------------------
-- RÉSEAU
----------------------------------------------------------------------

net.Receive("CAR_RADIO_Play", function()
    local veh = net.ReadEntity()
    local url = net.ReadString()
    local startServerTime = net.ReadFloat()
    _ = net.ReadString() -- 'by' (pas utilisé ici)
    local initiatorSID64_or_gainMaybe = net.ReadString() -- compat: certains serveurs envoient SID64 ici
    local maybeGain = tonumber(initiatorSID64_or_gainMaybe)
    local initiatorSID64, gain

    if maybeGain then
        initiatorSID64 = ""        -- ancien serveur: pas d'info initiateur
        gain = maybeGain
    else
        initiatorSID64 = initiatorSID64_or_gainMaybe or ""
        gain = net.ReadFloat() or 1
    end

    if not IsValid(veh) or not veh:IsVehicle() then return end
    local idx = veh:EntIndex()
    Radios[idx] = Radios[idx] or { veh = veh }
    local R = Radios[idx]
    R.veh = veh
    R.url = url
    R.started = startServerTime
    R.gain = math.Clamp(gain or 1, 0, 1)
    R.radius = radius()
    R.falloff = falloff()
    R.lastSeenInRangeAt = 0
    R.initiatorSID64 = initiatorSID64 or ""

    -- IMPORTANT : si je ne suis pas l'initiateur ET pas encore unlock → montrer la barre
    if not AudioUnlockedGlobal then
        local lp = LocalPlayer()
        if IsValid(lp) then
            local mySID = lp:SteamID64() or ""
            local imInitiator = (R.initiatorSID64 ~= "" and R.initiatorSID64 == mySID)
            if not imInitiator then
                EnsureGlobalUnlockUI()
            end
        else
            -- fallback : on montre quand même la barre
            EnsureGlobalUnlockUI()
        end
    end
end)

net.Receive("CAR_RADIO_SetGain", function()
    local veh = net.ReadEntity()
    local g = math.Clamp(net.ReadFloat() or 1, 0, 1)
    if not IsValid(veh) then return end
    local R = Radios[veh:EntIndex()]
    if R then R.gain = g end
end)

net.Receive("CAR_RADIO_Stop", function()
    local veh = net.ReadEntity()
    if not IsValid(veh) then return end
    local idx = veh:EntIndex()
    local R = Radios[idx]
    if R then
        if IsValid(R.panel) then R.panel:QueueJavascript("try{ stop(); setVol(0); }catch(e){}"); R.panel:Remove() end
        Radios[idx] = nil
    end
end)

----------------------------------------------------------------------
-- TICK (création panels & application volume)
----------------------------------------------------------------------

local NEXT = 0
hook.Add("Think", "CAR_RADIO_Update_10Hz", function()
    if CurTime() < NEXT then return end
    NEXT = CurTime() + 0.1
    if table.IsEmpty(Radios) then return end

    local lp = LocalPlayer(); if not IsValid(lp) then return end
    local mySID = lp:SteamID64() or ""

    for idx, R in pairs(Radios) do
        local veh = R.veh
        if not IsValid(veh) then
            if IsValid(R.panel) then R.panel:Remove() end
            Radios[idx] = nil
            continue
        end

        R.radius = radius()
        R.falloff = falloff()

        local dist = lp:GetPos():Distance(veh:GetPos())
        local inRange = dist < R.radius

        if inRange then
            R.lastSeenInRangeAt = CurTime()

            if not IsValid(R.panel) then
                local imInitiator = (R.initiatorSID64 ~= "" and R.initiatorSID64 == mySID)
                -- fallback au conducteur si pas d'info initiateur
                if (R.initiatorSID64 == "" or R.initiatorSID64 == nil) then
                    if lp:InVehicle() and lp:GetVehicle() == veh and veh:GetDriver() == lp then
                        imInitiator = true
                    end
                end

                if imInitiator then
                    -- Pop-up 1 clic uniquement pour l'initiateur
                    EnsureAudioUnlockedForInitiator(idx, R.url or "", CurTime() - (R.started or CurTime()), function(recycled)
                        if recycled then R.panel = recycled; R.lastVol = nil end
                    end)
                else
                    -- Observateur : lecteur caché
                    local hidden = CreateHiddenContainer()
                    local pnl = vgui.Create("DHTML", hidden)
                    pnl:SetSize(hidden:GetWide(), hidden:GetTall())
                    pnl:SetPos(0, 0)
                    pnl:SetHTML(HtmlPage())
                    function pnl:OnDocumentReady(_)
                        local qurl = js_quote(R.url or "")
                        local seek = math.max(0, math.floor(CurTime() - (R.started or CurTime())))
                        -- setVol(30) même si ready pas encore true, sera appliqué via pendingVol
                        self:QueueJavascript(("try{ setUrl(%s); setVol(30); seekPlay(%d); }catch(e){}"):format(qurl, seek))
                        -- si déjà unlock global → wake + légère hausse
                        if AudioUnlockedGlobal then
                            timer.Simple(0.3, function()
                                if IsValid(self) then self:QueueJavascript("try{ wake(); setVol(40); }catch(e){}") end
                            end)
                        end
                    end
                    R.panel = pnl
                    R.lastVol = nil
                end
            end

            if IsValid(R.panel) then
                local t = 1 - (dist / R.radius)
                local base = math.Clamp(math.pow(t, R.falloff), 0, 1)
                local g = math.Clamp(R.gain or 1, 0, 1)
                local vol = math.floor(base * g * 100)
                if R.lastVol ~= vol then
                    R.panel:QueueJavascript(("try{ setVol(%d); }catch(e){}"):format(vol))
                    R.lastVol = vol
                end
            end
        else
            if IsValid(R.panel) then
                if (R.lastVol or 1) ~= 0 then
                    R.panel:QueueJavascript("try{ setVol(0); }catch(e){}")
                    R.lastVol = 0
                end
                if (CurTime() - (R.lastSeenInRangeAt or 0)) > 8 then
                    R.panel:Remove()
                    R.panel = nil
                end
            end
        end
    end
end)

-- Commandes utilitaires (inchangées)
concommand.Add("car_radio_menu", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:InVehicle() then
        chat.AddText(Color(255,100,100), "[CarRadio] ", color_white, "Monte dans un véhicule.")
        return
    end
    if isfunction(CAR_RADIO_OpenMenu) then CAR_RADIO_OpenMenu(lp:GetVehicle())
    else chat.AddText(Color(255,100,100), "[CarRadio] ", color_white, "UI pas prête.") end
end)

concommand.Add("car_radio_stop", function()
    local lp = LocalPlayer(); if not IsValid(lp) or not lp:InVehicle() then return end
    net.Start("CAR_RADIO_RequestStop"); net.WriteEntity(lp:GetVehicle()); net.SendToServer()
end)
