-- sv_car_radio.lua — conducteur-only + 1 voiture max + whitelist + GAIN véhicule + garde licence
if not SERVER then return end

util.AddNetworkString("CAR_RADIO_RequestPlay")
util.AddNetworkString("CAR_RADIO_RequestStop")
util.AddNetworkString("CAR_RADIO_Play")
util.AddNetworkString("CAR_RADIO_Stop")
util.AddNetworkString("CAR_RADIO_SetGain") -- slider volume

-- ===== Licence =====
local function Licensed()
    return _G.CAR_RADIO_LICENSE_VALID == true
end

-- ===== Autorisations (depuis config server) =====
_G.CAR_RADIO_AUTH = _G.CAR_RADIO_AUTH or { allow_all = true, allowed = {} }
local function IsPlyAllowed(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local auth = _G.CAR_RADIO_AUTH
    if not auth then return true end
    if auth.allow_all then return true end
    local sid = ply:SteamID64() or ""
    return auth.allowed[sid] and true or false
end

-- ===== État =====
local ActiveByVeh      = ActiveByVeh or {} -- [vehIdx] = { url, startServerTime, byName, bySID64, lastChange, gain = 1 }
local LastPlayByPly    = LastPlayByPly or {}
local SyncPlayers      = SyncPlayers or {}
local DriverCapBySID64 = DriverCapBySID64 or {}

local cv_radius         = GetConVar("car_radio_radius")
local cv_sync_hz        = GetConVar("car_radio_sync_hz")
local cv_ply_cd         = GetConVar("car_radio_player_cooldown")
local cv_veh_cd         = GetConVar("car_radio_vehicle_cooldown")
local cv_max_len        = GetConVar("car_radio_url_maxlen")
local cv_max_active     = GetConVar("car_radio_max_active")
local cv_cap_per_driver = GetConVar("car_radio_cap_per_driver")
local cv_allow_replace  = GetConVar("car_radio_allow_replace")

local function isDriverOnly(ply, veh) return IsValid(ply) and IsValid(veh) and veh:GetDriver() == ply end
local function countActive() local c=0 for _ in pairs(ActiveByVeh) do c=c+1 end return c end

local function sendPlayToRecipients(veh, url, startServerTime, by, recipients)
    if not Licensed() then return end
    if not IsValid(veh) then return end
    local radius = cv_radius:GetFloat()
    local gain = 1
    local d = ActiveByVeh[veh:EntIndex()]
    if d and d.gain then gain = d.gain end

    if recipients == nil then
        recipients = {}
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p:Alive() and p:GetPos():Distance(veh:GetPos()) <= radius * 1.2 then
                recipients[#recipients+1] = p
            end
        end
    end
    if #recipients == 0 then return end
    net.Start("CAR_RADIO_Play")
        net.WriteEntity(veh)
        net.WriteString(url or "")
        net.WriteFloat(startServerTime or CurTime())
        net.WriteString(by or "")
        net.WriteFloat(gain or 1)
    net.Send(recipients)
end

local function sendStopToAll(veh)
    if not Licensed() then return end
    if not IsValid(veh) then return end
    net.Start("CAR_RADIO_Stop")
        net.WriteEntity(veh)
    net.Broadcast()
end

-- ===== Handlers =====
net.Receive("CAR_RADIO_RequestPlay", function(_, ply)
    if not Licensed() then return end
    local veh = net.ReadEntity()
    local url = net.ReadString()
    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end

    if not IsPlyAllowed(ply) then ply:ChatPrint("[CarRadio] Vous n'êtes pas autorisé à utiliser la radio.") return end
    if not isDriverOnly(ply, veh) then ply:ChatPrint("[CarRadio] Seul le conducteur peut lancer la musique.") return end
    if not url or url == "" then ply:ChatPrint("[CarRadio] Merci de coller un lien YouTube.") return end
    if #url > cv_max_len:GetInt() then ply:ChatPrint("[CarRadio] URL trop longue.") return end

    local now   = CurTime()
    local sid64 = ply:SteamID64() or ""

    local pcd = cv_ply_cd:GetFloat()
    if (LastPlayByPly[ply] or 0) + pcd > now then
        ply:ChatPrint(string.format("[CarRadio] Patiente %.1fs.", (LastPlayByPly[ply] + pcd) - now)); return
    end

    if cv_cap_per_driver:GetBool() then
        local capVehIdx = DriverCapBySID64[sid64]
        if capVehIdx and ActiveByVeh[capVehIdx] and capVehIdx ~= veh:EntIndex() then
            ply:ChatPrint("[CarRadio] Vous avez déjà une musique active sur un autre véhicule."); return
        end
    end

    local idx = veh:EntIndex()
    local vd  = ActiveByVeh[idx]
    local vcd = cv_veh_cd:GetFloat()

    if vd then
        if not cv_allow_replace:GetBool() then ply:ChatPrint("[CarRadio] Une musique est déjà en cours sur ce véhicule."); return end
        if (vd.lastChange or 0) + vcd > now then ply:ChatPrint("[CarRadio] Trop rapide, attends un peu."); return end
    else
        if countActive() >= cv_max_active:GetInt() then ply:ChatPrint("[CarRadio] Trop de radios actives, réessaie plus tard."); return end
    end

    ActiveByVeh[idx] = ActiveByVeh[idx] or {}
    ActiveByVeh[idx].url = url
    ActiveByVeh[idx].startServerTime = now
    ActiveByVeh[idx].byName = ply:Nick()
    ActiveByVeh[idx].bySID64 = sid64
    ActiveByVeh[idx].lastChange = now
    ActiveByVeh[idx].gain = ActiveByVeh[idx].gain or 1

    if veh:GetDriver() == ply then DriverCapBySID64[sid64] = idx end
    LastPlayByPly[ply] = now

    ply:ChatPrint("[CarRadio] Lecture démarrée.")
    sendPlayToRecipients(veh, url, now, ply:Nick())
end)

net.Receive("CAR_RADIO_RequestStop", function(_, ply)
    if not Licensed() then return end
    local veh = net.ReadEntity()
    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end

    if not IsPlyAllowed(ply) then ply:ChatPrint("[CarRadio] Vous n'êtes pas autorisé à utiliser la radio.") return end
    if not isDriverOnly(ply, veh) then ply:ChatPrint("[CarRadio] Seul le conducteur peut arrêter la musique.") return end

    local idx = veh:EntIndex()
    local data = ActiveByVeh[idx]
    if data then
        ActiveByVeh[idx] = nil
        SyncPlayers[idx]  = nil
        if data.bySID64 and DriverCapBySID64[data.bySID64] == idx then DriverCapBySID64[data.bySID64] = nil end
        sendStopToAll(veh)
        ply:ChatPrint("[CarRadio] Radio arrêtée.")
    end
end)

-- Réception gain conducteur -> broadcast
net.Receive("CAR_RADIO_SetGain", function(_, ply)
    if not Licensed() then return end
    local veh = net.ReadEntity()
    local g   = math.Clamp(net.ReadFloat() or 1, 0, 1)
    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end
    if not IsPlyAllowed(ply) then return end
    if not isDriverOnly(ply, veh) then return end

    local idx = veh:EntIndex()
    if not ActiveByVeh[idx] then return end
    ActiveByVeh[idx].gain = g

    net.Start("CAR_RADIO_SetGain")
        net.WriteEntity(veh)
        net.WriteFloat(g)
    net.Broadcast()
end)

-- Nettoyage & sync
hook.Add("EntityRemoved","CAR_RADIO_Cleanup_Ent", function(ent)
    if not Licensed() then return end
    if not ent:IsVehicle() then return end
    local idx = ent:EntIndex()
    local data = ActiveByVeh[idx]
    ActiveByVeh[idx] = nil
    SyncPlayers[idx]  = nil
    if data and data.bySID64 and DriverCapBySID64[data.bySID64] == idx then
        DriverCapBySID64[data.bySID64] = nil
    end
    sendStopToAll(ent)
end)

hook.Add("PlayerLeaveVehicle", "CAR_RADIO_FreeCapOnLeave", function(ply, veh)
    if not Licensed() then return end
    if not IsValid(ply) or not IsValid(veh) then return end
    local idx = veh:EntIndex()
    local data = ActiveByVeh[idx]
    if data and data.bySID64 and DriverCapBySID64[data.bySID64] == idx and veh:GetDriver() ~= ply then
        DriverCapBySID64[data.bySID64] = nil
    end
end)

local function syncTick()
    if not Licensed() then return end
    if table.IsEmpty(ActiveByVeh) then return end
    local radius = cv_radius:GetFloat()
    for vehIdx, data in pairs(ActiveByVeh) do
        local veh = Entity(vehIdx)
        if not IsValid(veh) or not veh:IsVehicle() then
            ActiveByVeh[vehIdx] = nil
            SyncPlayers[vehIdx]  = nil
        else
            SyncPlayers[vehIdx] = SyncPlayers[vehIdx] or {}
            local recipients = {}
            for _, p in ipairs(player.GetAll()) do
                if IsValid(p) and p:Alive() then
                    local dist = p:GetPos():Distance(veh:GetPos())
                    local already = SyncPlayers[vehIdx][p]
                    if dist <= radius * 0.95 then
                        if not already then
                            recipients[#recipients+1] = p
                            SyncPlayers[vehIdx][p] = true
                        end
                    else
                        if already then SyncPlayers[vehIdx][p] = nil end
                    end
                end
            end
            if #recipients > 0 then
                sendPlayToRecipients(veh, data.url, data.startServerTime, data.byName, recipients)
            end
        end
    end
end

-- Création du timer de sync (existe toujours, mais ne fait rien tant que pas Licensed())
hook.Add("Initialize", "CAR_RADIO_MakeSyncTimer", function()
    timer.Create("CAR_RADIO_SyncTimer", 1 / math.max(0.2, GetConVar("car_radio_sync_hz"):GetFloat()), 0, syncTick)
end)

-- Garde anti-suppression du module licence
timer.Simple(0, function()
    if not _G.CAR_RADIO_LICENSE_OK then
        print("[CarRadio] Licence check manquante. Arrêt.")
        hook.Add("Think", "CAR_RADIO_LOCK", function() end)
    end
end)
