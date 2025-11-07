-- cl_car_radio.lua — gestion client complète de la Car Radio
if not CLIENT then return end

if istable(CAR_RADIO) and CAR_RADIO.__core_loaded then return end

CAR_RADIO = CAR_RADIO or {}
CAR_RADIO.__core_loaded = true

-- ====================================================================
--  État client
-- ====================================================================
-- Radios[vehIdx] = {
--     veh, url, videoId, started, gain, desiredVolume,
--     lastSentVolume, initiatorSID64, byName
-- }
local Radios = Radios or {}

local Master = {
    frame = nil,
    html = nil,
    hidden = nil,
    unlocked = false
}

-- ====================================================================
--  Helpers
-- ====================================================================
local function radius()  return GetConVar("car_radio_radius"):GetFloat() end
local function falloff() return math.max(0.2, GetConVar("car_radio_falloff"):GetFloat()) end

local function js_quote(str)
    str = tostring(str or "")
    local json = util.TableToJSON({ str })
    local quoted = json and json:match("^%[(.*)%]$")
    if not quoted then
        str = str:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"):gsub("\"", "\\\"")
        quoted = "\"" .. str .. "\""
    end
    return quoted
end

local function ExtractVideoID(url)
    if not isstring(url) then return nil end
    local clean = string.Trim(url)
    if clean == "" then return nil end

    local patterns = {
        "youtu%.be/([A-Za-z0-9_-]+)",
        "youtube%.com/watch%?[^#]*v=([A-Za-z0-9_-]+)",
        "youtube%.com/embed/([A-Za-z0-9_-]+)",
        "youtube%.com/v/([A-Za-z0-9_-]+)",
        "youtube%.com/shorts/([A-Za-z0-9_-]+)"
    }

    for _, patt in ipairs(patterns) do
        local id = clean:match(patt)
        if id and #id >= 6 then
            id = id:match("^[A-Za-z0-9_-]+")
            if id and #id == 11 then return id end
        end
    end

    local fallback = clean:match("([A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-])")
    if fallback and #fallback == 11 then return fallback end
    return nil
end

local function CreateHiddenParent()
    if IsValid(Master.hidden) then return Master.hidden end
    local pnl = vgui.Create("DPanel")
    pnl:SetSize(320, 200)
    pnl:SetPos(ScrW() + 100, 50)
    pnl:SetVisible(true)
    pnl:SetMouseInputEnabled(false)
    pnl:SetKeyboardInputEnabled(false)
    Master.hidden = pnl
    return pnl
end

local function HtmlPage()
    return [[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
html,body{margin:0;padding:0;background:#05070c;color:#fff;font-family:Arial,Helvetica,sans-serif;height:100%;overflow:hidden;}
#overlay{position:absolute;inset:0;background:radial-gradient(circle at 20% 20%,rgba(25,40,70,0.9),rgba(8,12,20,0.94));display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;text-align:center;}
body.unlocked #overlay{display:none;}
#unlockBtn{padding:18px 26px;border:2px solid rgba(120,200,255,0.85);border-radius:22px;font-size:18px;letter-spacing:.08em;text-transform:uppercase;background:rgba(15,22,36,0.9);cursor:pointer;transition:all .2s ease;box-shadow:0 0 14px rgba(70,120,200,0.45);}
#unlockBtn:hover{border-color:rgba(160,220,255,1);box-shadow:0 0 18px rgba(120,200,255,0.6);}
#info{font-size:13px;color:rgba(200,220,255,0.75);}
#players{position:absolute;left:-9999px;top:-9999px;width:320px;height:180px;overflow:hidden;}
.player{width:320px;height:180px;}
</style>
<script>
(function(){
  var unlocked=false;
  var players={};
  var pending=[];
  function loadAPI(){
    if(window.__ytRequested) return;
    window.__ytRequested=true;
    var tag=document.createElement('script');
    tag.src='https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);
  }
  function flush(){
    if(!unlocked || !window.YT || !window.YT.Player){ return; }
    var ops=pending.slice();
    pending.length=0;
    ops.forEach(function(fn){ try{ fn(); }catch(e){} });
  }
  window.onYouTubeIframeAPIReady=function(){ flush(); };
  function queue(fn){ pending.push(fn); loadAPI(); flush(); }
  function ensureContainer(id){
    var holder=document.getElementById('players');
    var node=document.getElementById('player-'+id);
    if(node) return node;
    node=document.createElement('div');
    node.id='player-'+id;
    node.className='player';
    holder.appendChild(node);
    return node;
  }
  function ensurePlayer(id){
    if(players[id]) return players[id];
    var node=ensureContainer(id);
    var player=new YT.Player(node.id,{
      width:'320',height:'180',
      playerVars:{autoplay:1,controls:0,disablekb:1,fs:0,rel:0,iv_load_policy:3,modestbranding:1,playsinline:1,enablejsapi:1},
      events:{
        onStateChange:function(evt){
          if(evt && evt.data===0 && window.gmod && gmod.VideoEnded){ try{ gmod.VideoEnded(id); }catch(e){} }
        },
        onError:function(evt){
          if(window.gmod && gmod.VideoError){
            var code = evt && evt.data ? evt.data : 0;
            try{ gmod.VideoError(id, code); }catch(e){}
          }
        }
      }
    });
    players[id]=player;
    return player;
  }
  function setVideo(id, videoId, startSeconds){
    queue(function(){
      var player=ensurePlayer(id);
      if(!player) return;
      try{
        player.loadVideoById({videoId:videoId,startSeconds:startSeconds||0,suggestedQuality:'default'});
        player.playVideo();
      }catch(e){}
    });
  }
  function setVolume(id, volume){
    queue(function(){
      var player=players[id];
      if(!player) return;
      volume=Math.max(0, Math.min(100, volume||0));
      try{
        if(volume<=0){ player.mute(); }
        else { player.unMute(); player.setVolume(volume); }
      }catch(e){}
    });
  }
  function stop(id){
    queue(function(){
      var player=players[id];
      if(!player) return;
      try{ player.stopVideo(); }catch(e){}
    });
  }
  function destroy(id){
    queue(function(){
      var player=players[id];
      if(player){ try{ player.destroy(); }catch(e){} }
      delete players[id];
      var node=document.getElementById('player-'+id);
      if(node && node.parentNode){ node.parentNode.removeChild(node); }
    });
  }
  window.CAR_RADIO = {
    setVideo:setVideo,
    setVolume:setVolume,
    stop:stop,
    destroy:destroy,
    flush:flush
  };
  window.CAR_RADIO_Unlock=function(){
    if(unlocked) return;
    unlocked=true;
    document.body.classList.add('unlocked');
    try{ if(window.gmod && gmod.Unlocked){ gmod.Unlocked(); } }catch(e){}
    flush();
  };
  document.addEventListener('DOMContentLoaded', function(){
    loadAPI();
    var btn=document.getElementById('unlockBtn');
    if(btn){ btn.addEventListener('click', window.CAR_RADIO_Unlock); }
  });
  window.addEventListener('keydown', function(evt){ if(evt.key==='Enter'){ window.CAR_RADIO_Unlock(); } });
})();
</script>
</head>
<body>
<div id="overlay">
  <div id="unlockBtn">Cliquer ici pour activer la radio</div>
  <div id="info">Un clic unique suffit pour toute la session.</div>
</div>
<div id="players"></div>
</body>
</html>
]]
end

local function EnsureMasterPanel(showPrompt)
    if IsValid(Master.html) then
        if showPrompt and not Master.unlocked and IsValid(Master.frame) then
            Master.frame:SetVisible(true)
            Master.frame:MakePopup()
        end
        return Master.html
    end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Car Radio — Activer l'audio")
    frame:SetSize(420, 280)
    frame:Center()
    frame:SetSizable(false)
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame:DockPadding(14, 60, 14, 14)

    function frame:Paint(w, h)
        draw.RoundedBox(16, 0, 0, w, h, Color(10, 12, 18, 245))
        surface.SetDrawColor(120, 200, 255, 110)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("Car Radio", "Trebuchet24", 18, 30, Color(220, 235, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Clique dans la fenêtre pour autoriser YouTube.", "Trebuchet18", 18, 54, Color(170, 190, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetText("✕")
    close:SetFont("Trebuchet18")
    close:SetSize(32, 32)
    close:SetPos(frame:GetWide() - 46, 18)
    close:SetTextColor(Color(220, 235, 255))
    close.Paint = function(self, w, h)
        draw.RoundedBox(10, 0, 0, w, h, self:IsHovered() and Color(150, 60, 60) or Color(110, 45, 45))
        draw.SimpleText("✕", "Trebuchet18", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    close.DoClick = function()
        frame:SetVisible(false)
    end
    frame.PerformLayout = function(self, w, h)
        if IsValid(close) then close:SetPos(w - 46, 18) end
    end

    local html = vgui.Create("DHTML", frame)
    html:Dock(FILL)
    html:SetHTML(HtmlPage())

    html:AddFunction("gmod", "Unlocked", function()
        if Master.unlocked then return end
        Master.unlocked = true
        local hidden = CreateHiddenParent()
        html:SetParent(hidden)
        html:SetSize(hidden:GetWide(), hidden:GetTall())
        html:SetPos(0, 0)
        if IsValid(frame) then frame:Close() end

        timer.Simple(0, function()
            if not IsValid(html) then return end
            local lp = LocalPlayer()
            for idx, R in pairs(Radios) do
                if R and R.videoId then
                    local offset = math.max(0, math.floor(CurTime() - (R.started or CurTime())))
                    html:QueueJavascript(string.format("window.CAR_RADIO.setVideo(%s,%s,%d);", js_quote(tostring(idx)), js_quote(R.videoId), offset))

                    local vol = 0
                    if IsValid(lp) and IsValid(R.veh) then
                        local dist = lp:GetPos():Distance(R.veh:GetPos())
                        local r = math.max(1, radius())
                        local t = 1 - math.Clamp(dist / r, 0, 1)
                        local base = math.Clamp(math.pow(t, falloff()), 0, 1)
                        vol = math.floor(math.Clamp(base * (R.gain or 1) * 100, 0, 100))
                    else
                        vol = math.floor(math.Clamp(R.desiredVolume or 0, 0, 100))
                    end

                    R.desiredVolume = vol
                    R.lastSentVolume = vol
                    html:QueueJavascript(string.format("window.CAR_RADIO.setVolume(%s,%d);", js_quote(tostring(idx)), vol))
                end
            end
            html:QueueJavascript("window.CAR_RADIO.flush();")
        end)

        chat.AddText(Color(120, 200, 255), "[CarRadio] ", color_white, "Audio YouTube débloqué pour cette session.")
    end)

    html:AddFunction("gmod", "VideoError", function(id, code)
        local vehIdx = tonumber(id)
        if not vehIdx then return end
        local R = Radios[vehIdx]
        if not R then return end
        local veh = R.veh
        local label = "ce véhicule"
        if IsValid(veh) then
            local driver = veh:GetDriver()
            if IsValid(driver) then
                label = string.format("%s (%s)", driver:Nick(), veh:GetClass())
            else
                label = veh:GetClass()
            end
        end
        chat.AddText(Color(255, 120, 120), "[CarRadio] ", color_white,
            string.format("Lecture bloquée pour %s (code %s).", label, tostring(code or "?")))
    end)

    html:AddFunction("gmod", "VideoEnded", function(id)
        local vehIdx = tonumber(id)
        if not vehIdx then return end
        local veh = Radios[vehIdx] and Radios[vehIdx].veh
        if not IsValid(veh) then return end
        local driver = veh:GetDriver()
        if IsValid(driver) and driver == LocalPlayer() then
            chat.AddText(Color(120, 200, 255), "[CarRadio] ", color_white, "La vidéo est terminée.")
        end
    end)

    Master.frame = frame
    Master.html = html

    if not showPrompt then
        frame:SetVisible(false)
    end

    return html
end

local function EnsureUnlockPrompt()
    EnsureMasterPanel(true)
end

local function SendJS(js)
    local html = EnsureMasterPanel(false)
    if not IsValid(html) then return end
    if Master.unlocked then
        html:QueueJavascript(js)
    end
end

local function EnsureRadioPlayback(idx)
    local R = Radios[idx]
    if not R or not R.videoId then return end
    if not Master.unlocked then return end
    local html = EnsureMasterPanel(false)
    if not IsValid(html) then return end
    local offset = math.max(0, math.floor(CurTime() - (R.started or CurTime())))
    html:QueueJavascript(string.format("window.CAR_RADIO.setVideo(%s,%s,%d);", js_quote(tostring(idx)), js_quote(R.videoId), offset))
    local desired = math.floor(math.Clamp(R.desiredVolume or 0, 0, 100))
    html:QueueJavascript(string.format("window.CAR_RADIO.setVolume(%s,%d);", js_quote(tostring(idx)), desired))
    R.lastSentVolume = desired
end

local function ApplyVolume(idx, vol)
    local R = Radios[idx]
    if not R then return end
    R.desiredVolume = vol
    if not Master.unlocked then return end
    local html = EnsureMasterPanel(false)
    if not IsValid(html) then return end
    local clamped = math.floor(math.Clamp(vol or 0, 0, 100))
    html:QueueJavascript(string.format("window.CAR_RADIO.setVolume(%s,%d);", js_quote(tostring(idx)), clamped))
    R.lastSentVolume = clamped
end

local function DestroyRadio(idx)
    local R = Radios[idx]
    if not R then return end
    if Master.unlocked then
        SendJS(string.format("window.CAR_RADIO.destroy(%s);", js_quote(tostring(idx))))
    end
    Radios[idx] = nil
end

-- ====================================================================
--  API publique
-- ====================================================================
function CAR_RADIO_GetVehicleGain(veh)
    if not IsValid(veh) then return 1 end
    local R = Radios[veh:EntIndex()]
    if not R then return 1 end
    return math.Clamp(R.gain or 1, 0, 1)
end

-- ====================================================================
--  Réseau
-- ====================================================================
net.Receive("CAR_RADIO_Play", function()
    local veh = net.ReadEntity()
    local url = net.ReadString()
    local started = net.ReadFloat()
    local byName = net.ReadString()
    local initiatorSID64 = net.ReadString()
    local gain = math.Clamp(net.ReadFloat() or 1, 0, 1)

    if not IsValid(veh) or not veh:IsVehicle() then return end

    local idx = veh:EntIndex()
    local videoId = ExtractVideoID(url)
    if not videoId then
        chat.AddText(Color(255, 120, 120), "[CarRadio] ", color_white,
            "Lien YouTube invalide reçu depuis le serveur.")
        return
    end

    Radios[idx] = Radios[idx] or {}
    local R = Radios[idx]
    R.veh = veh
    R.url = url
    R.videoId = videoId
    R.started = started or CurTime()
    R.gain = gain
    R.byName = byName or ""
    R.initiatorSID64 = initiatorSID64 or ""
    R.desiredVolume = R.desiredVolume or 0
    R.lastSentVolume = nil

    EnsureUnlockPrompt()
    EnsureRadioPlayback(idx)
end)

net.Receive("CAR_RADIO_SetGain", function()
    local veh = net.ReadEntity()
    local g = math.Clamp(net.ReadFloat() or 1, 0, 1)
    if not IsValid(veh) then return end
    local idx = veh:EntIndex()
    local R = Radios[idx]
    if not R then return end
    R.gain = g
    R.lastSentVolume = nil
end)

net.Receive("CAR_RADIO_Stop", function()
    local veh = net.ReadEntity()
    if not IsValid(veh) then return end
    DestroyRadio(veh:EntIndex())
end)

-- ====================================================================
--  Volume & maintenance
-- ====================================================================
local nextUpdate = 0
hook.Add("Think", "CAR_RADIO_ClientUpdate", function()
    if CurTime() < nextUpdate then return end
    nextUpdate = CurTime() + 0.1

    if not next(Radios) then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    for idx, R in pairs(Radios) do
        local veh = R.veh
        if not IsValid(veh) then
            DestroyRadio(idx)
            continue
        end

        if R.videoId and Master.unlocked and R.lastSentVolume == nil then
            EnsureRadioPlayback(idx)
        end

        local dist = lp:GetPos():Distance(veh:GetPos())
        local r = math.max(1, radius())
        local t = 1 - math.Clamp(dist / r, 0, 1)
        local base = math.Clamp(math.pow(t, falloff()), 0, 1)
        local vol = math.floor(math.Clamp(base * (R.gain or 1) * 100, 0, 100))

        if R.lastSentVolume ~= vol then
            ApplyVolume(idx, vol)
        end
    end
end)

-- Commande console pour réafficher la fenêtre manuellement
concommand.Add("car_radio_unlock", function()
    if Master.unlocked then
        chat.AddText(Color(120, 200, 255), "[CarRadio] ", color_white, "Audio déjà activé pour cette session.")
        return
    end
    EnsureUnlockPrompt()
    chat.AddText(Color(120, 200, 255), "[CarRadio] ", color_white,
        "Clique sur la fenêtre qui vient d'apparaître pour autoriser l'audio.")
end)
