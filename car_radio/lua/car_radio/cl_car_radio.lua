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
<style>
html,body{margin:0;padding:0;background:#05070c;color:#fff;font-family:Arial,Helvetica,sans-serif;height:100%;overflow:hidden}
#wrap{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at 20% 20%,#1c2942 0%,#10131c 55%,#05070c 100%)}
#player{position:relative;width:100%;height:100%;max-width:480px;aspect-ratio:16/9;border-radius:14px;overflow:hidden;box-shadow:0 8px 32px rgba(0,0,0,0.45)}
#unlock{position:absolute;inset:0;background:rgba(8,10,16,0.75);border:0;color:#fff;font-size:18px;letter-spacing:.08em;text-transform:uppercase;display:flex;align-items:center;justify-content:center;cursor:pointer;transition:all .2s ease;z-index:10}
#unlock.hidden{opacity:0;pointer-events:none}
#unlock span{padding:14px 18px;border:1px solid rgba(120,200,255,.7);border-radius:22px;background:rgba(17,24,36,.7);box-shadow:0 0 12px rgba(120,200,255,.25);}
#unlock:hover span{border-color:rgba(150,220,255,1);box-shadow:0 0 18px rgba(120,200,255,.45)}
#error{position:absolute;bottom:16px;left:50%;transform:translateX(-50%);background:rgba(180,60,60,.85);padding:10px 16px;border-radius:12px;font-size:13px;display:none;}
iframe{width:100%;height:100%;border:0;border-radius:14px;}
</style>
<script>
(function(){
  var apiRequested=false;
  var ready=false;
  var player=null;
  var pendingVol=35;
  var pendingId=null;
  var pendingSeek=0;
  var firstClickDone=false;

  function ensureAPI(){
    if(apiRequested) return;
    apiRequested=true;
    var tag=document.createElement('script');
    tag.src='https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);
  }

  window.onYouTubeIframeAPIReady=function(){
    player=new YT.Player('yt-frame',{
      videoId:'',
      width:'100%',
      height:'100%',
      playerVars:{
        autoplay:1,
        controls:1,
        disablekb:0,
        fs:0,
        rel:0,
        iv_load_policy:3,
        modestbranding:1,
        playsinline:1,
        enablejsapi:1
      },
      events:{
        onReady:onReady,
        onError:onError,
        onStateChange:onStateChange
      }
    });
  };

  function onReady(){
    ready=true;
    applyPending();
    if(firstClickDone){
      try{ player.playVideo(); }catch(e){}
    }
  }

  function onError(evt){
    try{
      showError('Lecture impossible (code '+evt.data+').');
      if(window.gmod&&gmod.OnPlayerError){ gmod.OnPlayerError(evt.data||0); }
    }catch(e){}
  }

  function onStateChange(evt){
    if(evt && evt.data===0){
      try{ if(window.gmod&&gmod.OnVideoEnded){ gmod.OnVideoEnded(); } }catch(e){}
    }
    if(evt && evt.data===1){ hideError(); }
  }

  function applyPending(){
    if(!ready||!player) return;
    try{
      if(pendingId){
        player.loadVideoById({videoId:pendingId,suggestedQuality:'default'});
        pendingId=null;
      }
      if(pendingSeek>0){ player.seekTo(pendingSeek,true); pendingSeek=0; }
      if(pendingVol<=0){ player.mute(); }
      else { player.unMute(); player.setVolume(pendingVol); }
      if(firstClickDone){ player.playVideo(); }
    }catch(e){}
  }

  function showError(msg){
    var el=document.getElementById('error');
    if(!el) return;
    el.textContent=msg||'Erreur de lecture.';
    el.style.display='block';
  }

  function hideError(){
    var el=document.getElementById('error');
    if(!el) return;
    el.style.display='none';
  }

  function extractID(url){
    if(!url) return null;
    try{
      var clean=url.trim();
      if(clean.indexOf('youtu.be/')>=0){
        clean=clean.split('youtu.be/')[1];
        clean=clean.split('?')[0].split('&')[0].split('#')[0];
        return clean;
      }
      var m=clean.match(/(?:v=|vi=)([A-Za-z0-9_-]{6,})/);
      if(m&&m[1]) return m[1];
      m=clean.match(/[A-Za-z0-9_-]{11}/);
      if(m&&m[0]) return m[0];
    }catch(e){}
    return null;
  }

  window.setUrl=function(url){
    var id=extractID(url);
    if(!id){ showError('URL YouTube invalide.'); return; }
    hideError();
    pendingId=id;
    ensureAPI();
    applyPending();
  };

  window.seekPlay=function(sec){
    var s=parseInt(sec||0,10);
    if(isNaN(s)||s<0) s=0;
    pendingSeek=s;
    ensureAPI();
    applyPending();
  };

  window.setVol=function(vol){
    var v=parseInt(vol||0,10);
    if(isNaN(v)) v=0;
    v=Math.max(0,Math.min(100,v));
    pendingVol=v;
    applyPending();
  };

  window.wake=function(){
    ensureAPI();
    firstClickDone=true;
    hideError();
    applyPending();
  };

  window.stop=function(){
    try{ if(player){ player.stopVideo(); } }catch(e){}
  };

  window.firstUserClick=function(){
    if(firstClickDone) return;
    firstClickDone=true;
    var btn=document.getElementById('unlock');
    if(btn){ btn.classList.add('hidden'); setTimeout(function(){ btn.remove(); },220); }
    pendingVol=Math.max(pendingVol,35);
    ensureAPI();
    applyPending();
    if(window.gmod && gmod.Interact){ try{ gmod.Interact(); }catch(e){} }
  };

  document.addEventListener('DOMContentLoaded',function(){
    ensureAPI();
    var btn=document.getElementById('unlock');
    if(btn){ btn.addEventListener('click', function(){ window.firstUserClick(); }, {passive:true}); }
  });
})();
</script></head><body>
<div id="wrap">
  <div id="player">
    <div id="unlock"><span>Activer l'audio</span></div>
    <iframe id="yt-frame" allow="autoplay; encrypted-media"></iframe>
    <div id="error">Erreur de lecture.</div>
  </div>
</div>
</body></html>
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
            R.panel:QueueJavascript("try{ wake(); setVol(40); }catch(e){}")
            R.lastVol = nil
        end
    end
end

local function SetupPanelCallbacks(panel, vehIdx)
    if not IsValid(panel) then return end

    panel:AddFunction("gmod", "OnPlayerError", function(code)
        local veh = Radios[vehIdx] and Radios[vehIdx].veh
        if not IsValid(veh) then return end
        local driver = veh:GetDriver()
        local vehicleName
        if IsValid(driver) then
            vehicleName = string.format("%s (%s)", driver:Nick(), veh:GetClass())
        else
            vehicleName = veh:GetClass()
        end

        chat.AddText(Color(255, 120, 120), "[CarRadio] ", color_white,
            string.format("Lecture YouTube bloquée pour %s (code %s).", vehicleName or "ce véhicule", tostring(code or "?")))
    end)

    panel:AddFunction("gmod", "OnVideoEnded", function()
        local veh = Radios[vehIdx] and Radios[vehIdx].veh
        if not IsValid(veh) then return end
        local driver = veh:GetDriver()
        if IsValid(driver) and driver == LocalPlayer() then
            chat.AddText(Color(120,200,255), "[CarRadio] ", color_white, "La vidéo est terminée.")
        end
    end)
end

local function PanelLoadMedia(panel, url, seekSeconds, initialVol)
    if not IsValid(panel) then return end
    local qurl = js_quote(url or "")
    local seek = math.max(0, math.floor(seekSeconds or 0))
    local vol = math.Clamp(math.floor(initialVol or 35), 0, 100)
    panel:QueueJavascript(("try{ setUrl(%s); setVol(%d); seekPlay(%d); }catch(e){}"):format(qurl, vol, seek))
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
    fr:SetSize(380, 58)
    fr:SetPos(ScrW() - fr:GetWide() - 16, 20)
    fr:SetZPos(10000)
    fr:SetMouseInputEnabled(true)
    fr:SetKeyboardInputEnabled(false)

    function fr:Paint(w,h)
        surface.SetDrawColor(12,14,20,230)
        surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(120,200,255,140)
        surface.DrawOutlinedRect(0,0,w,h,1)
        draw.SimpleText("Les radios sont en sourdine.", "Trebuchet18", 12, 16, Color(220,230,255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Clique pour autoriser l'audio YouTube.", "Trebuchet18", 12, h-18, Color(180,200,255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btn = vgui.Create("DButton", fr)
    btn:SetText("Débloquer maintenant")
    btn:SetFont("Trebuchet18")
    btn:SetWide(178); btn:SetTall(32)
    btn:SetPos(fr:GetWide()-btn:GetWide()-10, (fr:GetTall()-btn:GetTall())/2)
    btn:SetMouseInputEnabled(true)
    btn.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(90,140,220) or Color(70,110,180))
        draw.SimpleText(self:GetText(), "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
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
    frm:SetTitle("Car Radio — Débloquer le son")
    frm:SetSize(420, 280)
    frm:Center()
    frm:MakePopup()
    frm:SetSizable(false)

    local lbl = vgui.Create("DLabel", frm)
    lbl:Dock(TOP); lbl:DockMargin(14,12,14,6)
    lbl:SetText("Clique sur le bouton \"Activer l'audio\" ci-dessous pour autoriser YouTube à lire la vidéo.")
    lbl:SetWrap(true)
    lbl:SetTextColor(Color(230,230,230))

    local dhtml = vgui.Create("DHTML", frm)
    dhtml:Dock(FILL); dhtml:DockMargin(14,4,14,14)
    dhtml:SetHTML(HtmlPage())
    SetupPanelCallbacks(dhtml, vehIdx)

    BootstrapCtx = { frame = frm, dhtml = dhtml, vehIdx = vehIdx }

    dhtml:AddFunction("gmod","Interact", function()
        PanelLoadMedia(dhtml, url or "", seekSeconds, 45)

        -- 🔹 ferme automatiquement après 1 seconde
        timer.Simple(1, function()
            if not IsValid(frm) or not IsValid(dhtml) then return end
            local hidden = CreateHiddenContainer()
            dhtml:SetParent(hidden)
            dhtml:SetSize(hidden:GetWide(), hidden:GetTall())
            dhtml:SetPos(0, 0)
            SetupPanelCallbacks(dhtml, vehIdx)
            if onReadyWithPanel then onReadyWithPanel(dhtml) end
            if IsValid(frm) then frm:Close() end
            BootstrapCtx = nil
        end)
    end)

    function dhtml:OnDocumentReady(_)
        PanelLoadMedia(self, url or "", seekSeconds, 40)
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

    if IsValid(R.panel) then
        local sinceStart = CurTime() - (R.started or CurTime())
        PanelLoadMedia(R.panel, url or "", sinceStart, (R.lastVol or 40))
    end

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
                    SetupPanelCallbacks(pnl, idx)
                    function pnl:OnDocumentReady(_)
                        local seek = math.max(0, math.floor(CurTime() - (R.started or CurTime())))
                        PanelLoadMedia(self, R.url or "", seek, 35)
                        -- si déjà unlock global → wake + légère hausse
                        if AudioUnlockedGlobal then
                            timer.Simple(0.3, function()
                                if IsValid(self) then self:QueueJavascript("try{ wake(); setVol(45); }catch(e){}") end
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
