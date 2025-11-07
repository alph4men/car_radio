-- sv_car_radio_config.lua (panneau admin + persistance config + whitelist)
if not SERVER then return end

util.AddNetworkString("CAR_RADIO_AdminOpen")
util.AddNetworkString("CAR_RADIO_ConfigSnapshot")
util.AddNetworkString("CAR_RADIO_ConfigApply")
util.AddNetworkString("CAR_RADIO_ConfigSaved")

-- Whitelist (nouveaux net messages)
util.AddNetworkString("CAR_RADIO_AuthOpen")
util.AddNetworkString("CAR_RADIO_AuthSnapshot")
util.AddNetworkString("CAR_RADIO_AuthApply")
util.AddNetworkString("CAR_RADIO_AuthSaved")

local DATA_DIR   = "car_radio"
local CFG_FILE   = DATA_DIR .. "/config.json"
local AUTH_FILE  = DATA_DIR .. "/whitelist.json"

-- ===== Config ConVars (déjà existants) =====
local SCHEMA = {
    car_radio_radius             = { type="float", min=100,  max=5000 },
    car_radio_falloff            = { type="float", min=0.2,  max=4.0  },
    car_radio_allow_passengers   = { type="bool"  }, -- restera ignoré côté serveur si tu veux conducteur-only
    car_radio_sync_hz            = { type="float", min=0.2,  max=5.0  },
    car_radio_player_cooldown    = { type="float", min=0.0,  max=60.0 },
    car_radio_vehicle_cooldown   = { type="float", min=0.0,  max=60.0 },
    car_radio_url_maxlen         = { type="int",   min=32,   max=512  },
    car_radio_max_active         = { type="int",   min=1,    max=200  },
    car_radio_cap_per_driver     = { type="bool"  },
    car_radio_allow_replace      = { type="bool"  },
}

-- ===== Helpers fichiers =====
local function ensureDir()
    if not file.Exists(DATA_DIR, "DATA") then file.CreateDir(DATA_DIR) end
end
local function readText(p)
    ensureDir()
    if not file.Exists(p, "DATA") then return nil end
    return file.Read(p, "DATA")
end
local function writeText(p, t)
    ensureDir()
    file.Write(p, t)
end

-- ====== Snapshot / Apply ConVars ======
local function snapshotConvars()
    local t = {}
    for k, meta in pairs(SCHEMA) do
        local cv = GetConVar(k)
        if cv then
            if meta.type == "bool" then t[k] = cv:GetBool()
            elseif meta.type == "int" then t[k] = cv:GetInt()
            else t[k] = cv:GetFloat() end
        end
    end
    return t
end

local function clampKey(k, v)
    local m = SCHEMA[k]
    if not m then return nil end
    if m.type == "bool" then
        return v and true or false
    elseif m.type == "int" then
        v = math.floor(tonumber(v) or 0)
        if m.min then v = math.max(m.min, v) end
        if m.max then v = math.min(m.max, v) end
        return v
    else
        v = tonumber(v) or 0
        if m.min then v = math.max(m.min, v) end
        if m.max then v = math.min(m.max, v) end
        return v
    end
end

local function applyConvars(tbl)
    for k, v in pairs(tbl or {}) do
        local vv = clampKey(k, v)
        if vv ~= nil then
            if SCHEMA[k].type == "bool" then
                RunConsoleCommand(k, vv and "1" or "0")
            else
                RunConsoleCommand(k, tostring(vv))
            end
        end
    end
end

-- ====== Config fichier ======
local function loadConfig()
    local txt = readText(CFG_FILE)
    if not txt or txt == "" then
        writeText(CFG_FILE, util.TableToJSON(snapshotConvars(), true))
        print("[CarRadio] config.json initialisé.")
        return
    end
    local ok, tbl = pcall(util.JSONToTable, txt)
    if not ok or type(tbl) ~= "table" then
        print("[CarRadio] ERREUR: config.json invalide, ignoré.")
        return
    end
    applyConvars(tbl)
    print("[CarRadio] config.json chargé.")
end
hook.Add("Initialize", "CAR_RADIO_LoadCfg", loadConfig)

-- ====== Whitelist ======
_G.CAR_RADIO_AUTH = _G.CAR_RADIO_AUTH or { allow_all = true, allowed = {} } -- allowed en set

local function loadWhitelist()
    local txt = readText(AUTH_FILE)
    if not txt or txt == "" then
        writeText(AUTH_FILE, util.TableToJSON({ allow_all = true, allowed = {} }, true))
        _G.CAR_RADIO_AUTH = { allow_all = true, allowed = {} }
        print("[CarRadio] whitelist.json initialisé (allow_all=true).")
        return
    end
    local ok, tbl = pcall(util.JSONToTable, txt)
    if not ok or type(tbl) ~= "table" then
        print("[CarRadio] ERREUR: whitelist.json invalide, ignoré.")
        return
    end
    local allow_all = tbl.allow_all and true or false
    local allowed_set = {}
    if istable(tbl.allowed) then
        for _, sid in ipairs(tbl.allowed) do
            if isstring(sid) and sid ~= "" then allowed_set[sid] = true end
        end
    end
    _G.CAR_RADIO_AUTH = { allow_all = allow_all, allowed = allowed_set }
    print(string.format("[CarRadio] whitelist.json chargé (allow_all=%s, %d autorisés).", tostring(allow_all), table.Count(allowed_set)))
end
hook.Add("Initialize", "CAR_RADIO_LoadAuth", loadWhitelist)

local function saveWhitelist()
    local auth = _G.CAR_RADIO_AUTH or { allow_all = true, allowed = {} }
    local list = {}
    for sid, ok in pairs(auth.allowed or {}) do
        if ok then list[#list+1] = sid end
    end
    table.sort(list)
    writeText(AUTH_FILE, util.TableToJSON({ allow_all = auth.allow_all and true or false, allowed = list }, true))
end

local function isAdmin(ply) return IsValid(ply) and ply:IsSuperAdmin() end

-- ====== Réseau admin : ConVars ======
local function sendConvarSnapshotTo(ply)
    local snap = snapshotConvars()
    net.Start("CAR_RADIO_ConfigSnapshot")
        net.WriteUInt(table.Count(snap), 8)
        for k, v in pairs(snap) do
            net.WriteString(k)
            local m = SCHEMA[k]
            if m.type == "bool" then net.WriteBool(v)
            elseif m.type == "int" then net.WriteInt(v, 16)
            else net.WriteFloat(v) end
        end
    net.Send(ply)
end

hook.Add("PlayerSay", "CAR_RADIO_AdminChatOpen", function(ply, text)
    if string.Trim(string.lower(text or "")) == "!carradio" and isAdmin(ply) then
        sendConvarSnapshotTo(ply)
        return ""
    end
end)

concommand.Add("car_radio_admin", function(ply)
    if not IsValid(ply) then return end
    if not isAdmin(ply) then ply:ChatPrint("[CarRadio] Superadmin requis.") return end
    sendConvarSnapshotTo(ply)
end)

net.Receive("CAR_RADIO_AdminOpen", function(_, ply)
    if not isAdmin(ply) then return end
    sendConvarSnapshotTo(ply)
end)

net.Receive("CAR_RADIO_ConfigApply", function(_, ply)
    if not isAdmin(ply) then return end
    local count = net.ReadUInt(8)
    local incoming = {}
    for i = 1, count do
        local key = net.ReadString()
        local m = SCHEMA[key]
        if m then
            if m.type == "bool" then incoming[key] = net.ReadBool()
            elseif m.type == "int" then incoming[key] = net.ReadInt(16)
            else incoming[key] = net.ReadFloat() end
        else
            _ = net.ReadFloat()
        end
    end
    local final = {}
    for k, v in pairs(incoming) do
        local vv = clampKey(k, v)
        if vv ~= nil then final[k] = vv end
    end
    applyConvars(final)
    writeText(CFG_FILE, util.TableToJSON(snapshotConvars(), true))
    net.Start("CAR_RADIO_ConfigSaved"); net.Send(ply)
    ply:ChatPrint("[CarRadio] Configuration appliquée et sauvegardée.")
end)

-- ====== Réseau admin : Whitelist ======
local function sendAuthSnapshotTo(ply)
    local auth = _G.CAR_RADIO_AUTH or { allow_all = true, allowed = {} }
    local list = {}
    for sid, ok in pairs(auth.allowed or {}) do
        if ok then
            local name = sid
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID64() == sid then name = p:Nick() .. " ("..sid..")"; break end
            end
            list[#list+1] = { sid = sid, label = name }
        end
    end
    table.sort(list, function(a,b) return a.sid < b.sid end)

    net.Start("CAR_RADIO_AuthSnapshot")
        net.WriteBool(auth.allow_all and true or false)
        net.WriteUInt(#list, 12)
        for _, row in ipairs(list) do
            net.WriteString(row.sid)
            net.WriteString(row.label or row.sid)
        end
    net.Send(ply)
end

net.Receive("CAR_RADIO_AuthOpen", function(_, ply)
    if not isAdmin(ply) then return end
    sendAuthSnapshotTo(ply)
end)

net.Receive("CAR_RADIO_AuthApply", function(_, ply)
    if not isAdmin(ply) then return end
    local allow_all = net.ReadBool()
    local n = net.ReadUInt(12)
    local newset = {}
    for i=1,n do
        local sid = net.ReadString()
        if isstring(sid) and sid ~= "" then
            newset[sid] = true
        end
    end
    _G.CAR_RADIO_AUTH = { allow_all = allow_all and true or false, allowed = newset }
    saveWhitelist()
    net.Start("CAR_RADIO_AuthSaved"); net.Send(ply)
    ply:ChatPrint("[CarRadio] Autorisations mises à jour.")
end)
