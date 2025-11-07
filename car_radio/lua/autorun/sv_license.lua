-- sv_license.lua — licence IP (fail-closed) + message rouge + détection IP robuste (override + ipify)
if not SERVER then return end

util.AddNetworkString("CAR_RADIO_LicenseWarn")

_G.CAR_RADIO_LICENSE_OK     = true
_G.CAR_RADIO_LICENSE_VALID  = false -- fail-closed par défaut

-- ⚠️ Remplace par ton JSON RAW
local LICENSE_URL = "https://raw.githubusercontent.com/alph4men/car_radio/main/license.json"

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
    _G.CAR_RADIO_LICENSE_VALID = false
    broadcastLicenseWarn(ipDisplay)
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

-- ========= CHECK =========
timer.Simple(5, function()
    resolveServerIPAsync(function(ip)
        print("[CarRadio] Vérification de licence pour: " .. tostring(ip))

        http.Fetch(
            LICENSE_URL,
            function(body)
                local ok, data = pcall(util.JSONToTable, body)
                if not ok or type(data) ~= "table" then
                    return licenseLockdown("Réponse de licence invalide.", ip)
                end

                if data.disabled then
                    local msg = isstring(data.message) and data.message or "Addon désactivé par l'auteur."
                    return licenseLockdown(msg, ip)
                end

                local list = istable(data.authorized_ips) and data.authorized_ips or {}
                local authorized = false
                for _, v in ipairs(list) do
                    if ipMatches(ip, v) then authorized = true break end
                end

                if authorized then
                    _G.CAR_RADIO_LICENSE_VALID = true
                    print("[CarRadio] ✅ Licence valide pour ce serveur (" .. ip .. ").")
                else
                    licenseLockdown("Licence invalide pour ce serveur.", ip)
                end
            end,
            function(err)
                licenseLockdown("Échec HTTP de vérification de licence : " .. tostring(err), ip)
            end
        )
    end)
end)
