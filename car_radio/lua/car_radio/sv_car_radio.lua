-- sv_car_radio.lua — serveur principal de la radio voiture
if not SERVER then return end

if istable(CAR_RADIO) and CAR_RADIO.__server_core_loaded then return end

CAR_RADIO = CAR_RADIO or {}
CAR_RADIO.__server_core_loaded = true

util.AddNetworkString("CAR_RADIO_RequestPlay")
util.AddNetworkString("CAR_RADIO_RequestStop")
util.AddNetworkString("CAR_RADIO_Play")
util.AddNetworkString("CAR_RADIO_Stop")
util.AddNetworkString("CAR_RADIO_SetGain")

-- =========================================================
--  Helpers licence & autorisations
-- =========================================================
local function Licensed()
    return _G.CAR_RADIO_LICENSE_VALID == true
end

_G.CAR_RADIO_AUTH = _G.CAR_RADIO_AUTH or { allow_all = true, allowed = {} }

local function IsAuthorized(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end

    local auth = _G.CAR_RADIO_AUTH
    if not auth or auth.allow_all then return true end

    local sid = ply:SteamID64() or ""
    return auth.allowed[sid] == true
end

-- =========================================================
--  État courant
-- =========================================================
local ActiveRadios      = ActiveRadios or {} -- [vehIdx] = { url, started, byName, bySID64, gain, controllerSID64 }
local SyncedPlayers     = SyncedPlayers or {} -- [vehIdx] = { [ply] = true }
local LastPlayByPlayer  = LastPlayByPlayer or {} -- [ply] = timestamp
local DriverCapBySID64  = DriverCapBySID64 or {} -- [sid64] = vehIdx

-- ConVars
local cv_radius         = GetConVar("car_radio_radius")
local cv_sync_hz        = GetConVar("car_radio_sync_hz")
local cv_ply_cd         = GetConVar("car_radio_player_cooldown")
local cv_veh_cd         = GetConVar("car_radio_vehicle_cooldown")
local cv_max_len        = GetConVar("car_radio_url_maxlen")
local cv_max_active     = GetConVar("car_radio_max_active")
local cv_cap_per_driver = GetConVar("car_radio_cap_per_driver")
local cv_allow_replace  = GetConVar("car_radio_allow_replace")
local cv_allow_pass     = GetConVar("car_radio_allow_passengers")

local function radius()
    return (cv_radius and cv_radius:GetFloat()) or 1200
end

local function allowPassengers()
    return cv_allow_pass and cv_allow_pass:GetBool()
end

local function CountActive()
    local c = 0
    for _ in pairs(ActiveRadios) do c = c + 1 end
    return c
end

local function CanControlVehicle(ply, veh)
    if not IsValid(ply) or not IsValid(veh) then return false end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return false end
    if allowPassengers() then
        return true
    end
    return veh:GetDriver() == ply
end

local function ControllerSID64(ply, veh)
    if not allowPassengers() then
        local driver = IsValid(veh) and veh:GetDriver()
        if IsValid(driver) then
            return driver:SteamID64() or ""
        end
    end
    return ply:SteamID64() or ""
end

local function SendPlay(veh, data, recipients)
    if not Licensed() then return end
    if not IsValid(veh) then return end

    if recipients == nil then
        recipients = {}
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p:Alive() then
                local distSqr = p:GetPos():DistToSqr(veh:GetPos())
                if distSqr <= (radius() * 1.2) ^ 2 then
                    recipients[#recipients + 1] = p
                end
            end
        end
    end

    if #recipients == 0 then return end

    local idx = veh:EntIndex()
    SyncedPlayers[idx] = SyncedPlayers[idx] or {}
    for _, ply in ipairs(recipients) do
        if IsValid(ply) then
            SyncedPlayers[idx][ply] = true
        end
    end

    net.Start("CAR_RADIO_Play")
        net.WriteEntity(veh)
        net.WriteString(data.url or "")
        net.WriteFloat(data.started or CurTime())
        net.WriteString(data.byName or "")
        net.WriteString(data.bySID64 or "")
        net.WriteFloat(math.Clamp(data.gain or 1, 0, 1))
    net.Send(recipients)
end

local function SendStop(veh, idx, recipients)
    if not Licensed() then return end
    if not IsValid(veh) then return end

    net.Start("CAR_RADIO_Stop")
        net.WriteEntity(veh)
    if recipients and #recipients > 0 then
        net.Send(recipients)
    else
        net.Broadcast()
    end
end

local function ResetSyncList(idx)
    SyncedPlayers[idx] = nil
end

local function SyncTick()
    if not Licensed() then return end
    if next(ActiveRadios) == nil then return end

    local r = radius()
    local rSqr = (r * 0.95) ^ 2
    local outerSqr = (r * 1.3) ^ 2

    for idx, data in pairs(ActiveRadios) do
        local veh = Entity(idx)
        if not IsValid(veh) or not veh:IsVehicle() then
            ActiveRadios[idx] = nil
            ResetSyncList(idx)
        else
            SyncedPlayers[idx] = SyncedPlayers[idx] or {}
            local toSend = {}

            for ply, _ in pairs(SyncedPlayers[idx]) do
                if not IsValid(ply) or not ply:Alive() then
                    SyncedPlayers[idx][ply] = nil
                elseif ply:GetPos():DistToSqr(veh:GetPos()) > outerSqr then
                    SyncedPlayers[idx][ply] = nil
                end
            end

            for _, ply in ipairs(player.GetAll()) do
                if not IsValid(ply) or not ply:Alive() then continue end
                if SyncedPlayers[idx][ply] then continue end
                if ply:GetPos():DistToSqr(veh:GetPos()) <= rSqr then
                    SyncedPlayers[idx][ply] = true
                    toSend[#toSend + 1] = ply
                end
            end

            if #toSend > 0 then
                SendPlay(veh, data, toSend)
            end
        end
    end
end

local function StopRadio(veh, idx)
    idx = idx or (IsValid(veh) and veh:EntIndex())
    if not idx then return end

    local data = ActiveRadios[idx]
    if not data then return end

    ActiveRadios[idx] = nil

    if data.controllerSID64 and DriverCapBySID64[data.controllerSID64] == idx then
        DriverCapBySID64[data.controllerSID64] = nil
    end

    local recipients = {}
    if SyncedPlayers[idx] then
        for ply, _ in pairs(SyncedPlayers[idx]) do
            if IsValid(ply) then
                recipients[#recipients + 1] = ply
            end
        end
    end
    ResetSyncList(idx)

    SendStop(veh, idx, recipients)
end

-- =========================================================
--  Réception Play / Stop / Gain
-- =========================================================
net.Receive("CAR_RADIO_RequestPlay", function(_, ply)
    if not Licensed() then return end

    local veh = net.ReadEntity()
    local url = net.ReadString()

    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end

    if not IsAuthorized(ply) then
        ply:ChatPrint("[CarRadio] Vous n'êtes pas autorisé à utiliser la radio.")
        return
    end

    if not CanControlVehicle(ply, veh) then
        ply:ChatPrint("[CarRadio] Seul le conducteur peut utiliser la radio.")
        return
    end

    if not url or url == "" then
        ply:ChatPrint("[CarRadio] Merci de coller un lien YouTube.")
        return
    end

    local maxLen = (cv_max_len and cv_max_len:GetInt()) or 200
    if #url > maxLen then
        ply:ChatPrint("[CarRadio] URL trop longue.")
        return
    end

    local now = CurTime()
    local sid64 = ply:SteamID64() or ""

    local plyCooldown = (cv_ply_cd and cv_ply_cd:GetFloat()) or 0
    local last = LastPlayByPlayer[ply] or 0
    if last + plyCooldown > now then
        ply:ChatPrint(string.format("[CarRadio] Patiente %.1fs avant de relancer.", (last + plyCooldown) - now))
        return
    end

    local idx = veh:EntIndex()
    local existing = ActiveRadios[idx]
    local vehCooldown = (cv_veh_cd and cv_veh_cd:GetFloat()) or 0

    if existing then
        if not (cv_allow_replace and cv_allow_replace:GetBool()) then
            ply:ChatPrint("[CarRadio] Une musique est déjà en cours sur ce véhicule.")
            return
        end
        if (existing.lastChange or 0) + vehCooldown > now then
            ply:ChatPrint("[CarRadio] Trop rapide, attends un peu.")
            return
        end
    else
        local maxActive = (cv_max_active and cv_max_active:GetInt()) or 50
        if CountActive() >= maxActive then
            ply:ChatPrint("[CarRadio] Trop de radios actives, réessaie plus tard.")
            return
        end
    end

    if cv_cap_per_driver and cv_cap_per_driver:GetBool() then
        local controllerSID = ControllerSID64(ply, veh)
        local capIdx = DriverCapBySID64[controllerSID]
        if capIdx and ActiveRadios[capIdx] and capIdx ~= idx then
            ply:ChatPrint("[CarRadio] Vous avez déjà une radio active sur un autre véhicule.")
            return
        end
    end

    ActiveRadios[idx] = ActiveRadios[idx] or {}
    ActiveRadios[idx].url = url
    ActiveRadios[idx].started = now
    ActiveRadios[idx].byName = ply:Nick()
    ActiveRadios[idx].bySID64 = sid64
    ActiveRadios[idx].gain = ActiveRadios[idx].gain or 1
    ActiveRadios[idx].lastChange = now
    ActiveRadios[idx].controllerSID64 = ControllerSID64(ply, veh)

    DriverCapBySID64[ActiveRadios[idx].controllerSID64] = idx
    LastPlayByPlayer[ply] = now

    SyncedPlayers[idx] = SyncedPlayers[idx] or {}
    SyncedPlayers[idx][ply] = true

    ply:ChatPrint("[CarRadio] Lecture démarrée.")
    SendPlay(veh, ActiveRadios[idx], nil)
end)

net.Receive("CAR_RADIO_RequestStop", function(_, ply)
    if not Licensed() then return end

    local veh = net.ReadEntity()
    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end

    if not IsAuthorized(ply) then return end
    if not CanControlVehicle(ply, veh) then return end

    StopRadio(veh, veh:EntIndex())
    ply:ChatPrint("[CarRadio] Radio arrêtée.")
end)

net.Receive("CAR_RADIO_SetGain", function(_, ply)
    if not Licensed() then return end

    local veh = net.ReadEntity()
    local gain = math.Clamp(net.ReadFloat() or 1, 0, 1)

    if not IsValid(ply) or not IsValid(veh) or not veh:IsVehicle() then return end
    if not ply:InVehicle() or ply:GetVehicle() ~= veh then return end

    if not IsAuthorized(ply) then return end
    if not CanControlVehicle(ply, veh) then return end

    local idx = veh:EntIndex()
    local data = ActiveRadios[idx]
    if not data then return end

    data.gain = gain

    net.Start("CAR_RADIO_SetGain")
        net.WriteEntity(veh)
        net.WriteFloat(gain)
    net.Broadcast()
end)

-- =========================================================
--  Nettoyage & synchronisation
-- =========================================================
hook.Add("EntityRemoved", "CAR_RADIO_CleanupVehicle", function(ent)
    if not ent:IsVehicle() then return end
    StopRadio(ent, ent:EntIndex())
end)

hook.Add("PlayerLeaveVehicle", "CAR_RADIO_ReleaseCap", function(ply, veh)
    if not IsValid(ply) or not IsValid(veh) then return end
    local idx = veh:EntIndex()
    local data = ActiveRadios[idx]
    if data and data.controllerSID64 and DriverCapBySID64[data.controllerSID64] == idx then
        DriverCapBySID64[data.controllerSID64] = nil
    end
end)

hook.Add("PlayerDisconnected", "CAR_RADIO_ClearCooldown", function(ply)
    LastPlayByPlayer[ply] = nil
end)

hook.Add("Initialize", "CAR_RADIO_StartSync", function()
    local hz = math.max(0.2, cv_sync_hz and cv_sync_hz:GetFloat() or 1)
    timer.Create("CAR_RADIO_Sync", 1 / hz, 0, SyncTick)
end)

-- Licence guard
hook.Add("InitPostEntity", "CAR_RADIO_CheckLicense", function()
    if not _G.CAR_RADIO_LICENSE_OK then
        print("[CarRadio] Licence invalide : désactivation.")
        hook.Add("Think", "CAR_RADIO_LOCKED", function() end)
    end
end)
