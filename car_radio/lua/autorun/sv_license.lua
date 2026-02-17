-- sv_license.lua — licence IP (fail-closed) + message rouge + détection IP robuste (override + ipify)
if not SERVER then return end

util.AddNetworkString("CAR_RADIO_LicenseWarn")

_G.CAR_RADIO_LICENSE_OK     = false
_G.CAR_RADIO_LICENSE_VALID  = false -- fail-closed par défaut

CreateConVar("car_radio_license_url", "https://raw.githubusercontent.com/alph4men/car_radio/main/license.json", { FCVAR_ARCHIVE }, "URL JSON distante de licence")

-- Override IP:PORT (convar ou data file)
CreateConVar("car_radio_license_ip_override", "", { FCVAR_ARCHIVE }, "Force l'IP:PORT pour la licence (ex: 51.222.145.32:27015)")
local OVERRIDE_FILE = "car_radio/ip_override.txt" -- contenu: "IP" ou "IP:PORT"

-- ========= UTILS =========
local function splitHostPort(addr)
    if not isstring(addr) then return tostring(addr or ""), nil end
    local host, port = string.match(addr, "^%s*([^:]+):?(%d*)%s*$")
    host = host or addr
    port = (port ~= nil and port ~= "") and tonumber(port) or nil
    return string.lower(string.Trim(host)), port
end

local function ipMatches(current, allowed)
    local ch, cp = splitHostPort(current)
    local ah, ap = splitHostPort(allowed)
    if ch ~= ah then return false end
    if ap == nil then return true end             -- entrée sans port: n'importe quel port
    return (cp ~= nil and cp == ap)               -- entrée avec port: port exact requis
end

local function readOverride()
    local cvar = GetConVarString("car_radio_license_ip_override") or ""
    if cvar ~= "" then return string.Trim(cvar) end
    if file.Exists(OVERRIDE_FILE, "DATA") then
        local txt = string.Trim(file.Read(OVERRIDE_FILE, "DATA") or "")
        if txt ~= "" then return txt end
    end
    return nil
end

local function broadcastLicenseWarn(ipStr)
    net.Start("CAR_RADIO_LicenseWarn")
        net.WriteString(tostring(ipStr or "inconnue"))
    net.Broadcast()
end

local function licenseLockdown(reason, ipDisplay)
    reason = reason or "Licence invalide."
    print("[CarRadio] 🚫 LOCKDOWN: " .. reason)
    _G.CAR_RADIO_LICENSE_OK = false
    _G.CAR_RADIO_LICENSE_VALID = false
    broadcastLicenseWarn(ipDisplay)
end

local function licenseUnlock(ipDisplay, sourceLabel)
    _G.CAR_RADIO_LICENSE_OK = true
    _G.CAR_RADIO_LICENSE_VALID = true
    local lbl = sourceLabel and (" via " .. sourceLabel) or ""
    print(string.format("[CarRadio] ✅ Licence valide pour ce serveur (%s%s).", tostring(ipDisplay), lbl))
end

local function decodeLicenseJSON(raw)
    if not isstring(raw) or raw == "" then return nil end
    local cleaned = raw
    cleaned = cleaned:gsub("//.-\n", "\n")
    cleaned = cleaned:gsub("//.-$", "")

    local ok, data = pcall(util.JSONToTable, cleaned)
    if ok and istable(data) then return data end

    ok, data = pcall(util.JSONToTable, raw)
    if ok and istable(data) then return data end

    return nil
end

local LOCAL_LICENSE_PATHS = {
    "addons/car_radio/license.json",
    "car_radio/license.json",
    "license.json",
}

local function readLocalLicenseFile()
    for _, path in ipairs(LOCAL_LICENSE_PATHS) do
        local f = file.Open(path, "r", "GAME")
        if f then
            local size = f:Size() or 0
            local body = size > 0 and f:Read(size) or ""
            f:Close()
            if isstring(body) and body ~= "" then
                return body, path
            end
        end
    end
    return nil, nil
end

local function processLicenseTable(tbl, ip, sourceLabel)
    if not istable(tbl) then
        return false, "Réponse de licence invalide."
    end

    if tbl.disabled then
        local msg = isstring(tbl.message) and tbl.message or "Addon désactivé par l'auteur."
        licenseLockdown(msg, ip)
        return true
    end

    local list = nil
    if istable(tbl.authorized_ips) then
        list = tbl.authorized_ips
    elseif istable(tbl.allowed_ips) then
        list = tbl.allowed_ips
    elseif istable(tbl.ips) then
        list = tbl.ips
    end
    if not list then
        return false, "Champ authorized_ips manquant."
    end

    local authorized = false
    for _, v in ipairs(list) do
        if ipMatches(ip, v) then authorized = true break end
    end

    if authorized then
        licenseUnlock(ip, sourceLabel)
        return true
    end

    licenseLockdown("Licence invalide pour ce serveur.", ip)
    return true
end

local function tryLocalFallback(ip, baseReason)
    local body, path = readLocalLicenseFile()
    if not body then
        licenseLockdown(baseReason or "Licence introuvable.", ip)
        return
    end

    local data = decodeLicenseJSON(body)
    if not data then
        licenseLockdown((baseReason or "Licence invalide.") .. " (fallback local corrompu)", ip)
        return
    end

    local handled, err = processLicenseTable(data, ip, path or "local")
    if handled then return end

    licenseLockdown((baseReason or "Licence invalide.") .. " (fallback local incomplet)", ip)
end

-- ========= RÉSOLUTION IP (sync + fallback HTTP) =========
-- Appelle cb(ip_string) avec une IP:PORT fiable (jamais 'unknown' si internet OK)
local function resolveServerIPAsync(cb)
    -- 1) Override prioritaire
    local ov = readOverride()
    if ov and ov ~= "" then cb(ov) return end

    -- 2) game.GetIPAddress
    local gip = game.GetIPAddress() or ""
    if gip ~= "" and gip ~= "0.0.0.0:0" then cb(gip) return end

    -- 3) hostip/hostport (listen/dédié sans annonce)
    local hostip  = GetConVarString("hostip") or ""
    local hostprt = tonumber(GetConVarString("hostport") or "") or 27015
    local n = tonumber(hostip)
    if n and n > 0 and bit then
        local function toA_B_C_D_LE(num)
            local b1 = bit.band(num, 0xFF)
            local b2 = bit.band(bit.rshift(num, 8), 0xFF)
            local b3 = bit.band(bit.rshift(num, 16), 0xFF)
            local b4 = bit.band(bit.rshift(num, 24), 0xFF)
            return string.format("%d.%d.%d.%d:%d", b1, b2, b3, b4, hostprt)
        end
        cb(toA_B_C_D_LE(n)) ; return
    end

    -- 4) Fallback public IP via ipify (dernière chance) → ajoute hostport
    HTTP({
        url = "https://api.ipify.org?format=json",
        method = "GET",
        success = function(code, body)
            local ipOnly = nil
            if tonumber(code) == 200 and isstring(body) then
                local ok, data = pcall(util.JSONToTable, body)
                if ok and istable(data) and isstring(data.ip) and data.ip ~= "" then
                    ipOnly = data.ip
                end
            end
            local port = tonumber(GetConVarString("hostport") or "") or 27015
            if ipOnly then
                cb( string.format("%s:%d", ipOnly, port) )
            else
                cb( "127.0.0.1:" .. port ) -- au pire, mais ce ne sera pas 'unknown'
            end
        end,
        failed = function(err)
            local port = tonumber(GetConVarString("hostport") or "") or 27015
            cb( "127.0.0.1:" .. port )
        end
    })
end

local function runLicenseCheck()
    resolveServerIPAsync(function(ip)
        print("[CarRadio] Vérification de licence pour: " .. tostring(ip))

        local function handleBadRemote(reason)
            tryLocalFallback(ip, reason or "Licence distante indisponible.")
        end

        local licenseUrl = GetConVarString("car_radio_license_url")
        if not isstring(licenseUrl) or licenseUrl == "" then
            licenseUrl = "https://raw.githubusercontent.com/alph4men/car_radio/main/license.json"
        end

        http.Fetch(
            licenseUrl,
            function(body)
                local data = decodeLicenseJSON(body)
                if not data then
                    handleBadRemote("Réponse de licence invalide.")
                    return
                end

                local handled, err = processLicenseTable(data, ip, "GitHub")
                if handled then return end

                handleBadRemote(err or "Données de licence incomplètes.")
            end,
            function(err)
                handleBadRemote("Échec HTTP de vérification de licence : " .. tostring(err))
            end
        )
    end)
end

-- ========= CHECK =========
timer.Simple(5, runLicenseCheck)
timer.Create("CAR_RADIO_LicenseRecheck", 300, 0, runLicenseCheck)
