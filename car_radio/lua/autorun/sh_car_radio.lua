-- sh_car_radio.lua
if SERVER then
    AddCSLuaFile("autorun/sh_car_radio.lua")

    -- Serveur
    AddCSLuaFile("autorun/sv_car_radio.lua")
    AddCSLuaFile("autorun/sv_car_radio_config.lua")

    -- Client : on s’assure de l’ordre (UI -> core -> HUD -> admin)
    AddCSLuaFile("car_radio/cl_player_ui.lua")
    AddCSLuaFile("car_radio/cl_car_radio.lua")
    AddCSLuaFile("car_radio/cl_driver_hud.lua")
    AddCSLuaFile("car_radio/cl_admin_config.lua")
end

-- Bootstrap client dans le BON ordre
if CLIENT then
    include("car_radio/cl_player_ui.lua")     -- définit CAR_RADIO_OpenMenu
    include("car_radio/cl_car_radio.lua")      -- crée les concommands & net receivers
    include("car_radio/cl_driver_hud.lua")     -- HUD (utilise OpenMenu, déjà défini)
    include("car_radio/cl_admin_config.lua")   -- panneau admin
end

CAR_RADIO = CAR_RADIO or {}
CAR_RADIO.Version = "1.3.2"

-- ConVars (défauts)
CreateConVar("car_radio_radius", "1200", { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Rayon audible autour du véhicule (units)")
CreateConVar("car_radio_falloff", "1.3", { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Puissance de décroissance du volume (>=0.2)")
CreateConVar("car_radio_allow_passengers", "1", { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "1 = passagers autorisés, 0 = conducteur seul")

CreateConVar("car_radio_sync_hz", "1", { FCVAR_ARCHIVE }, "Fréquence de sync (Hz)")
CreateConVar("car_radio_player_cooldown", "5", { FCVAR_ARCHIVE }, "Cooldown (s) par joueur")
CreateConVar("car_radio_vehicle_cooldown", "2", { FCVAR_ARCHIVE }, "Cooldown (s) par véhicule")
CreateConVar("car_radio_url_maxlen", "200", { FCVAR_ARCHIVE }, "Longueur max URL")
CreateConVar("car_radio_max_active", "50", { FCVAR_ARCHIVE }, "Radios max simultanées")

CreateConVar("car_radio_cap_per_driver", "1", { FCVAR_ARCHIVE }, "Cap conducteur: 1=on")
CreateConVar("car_radio_allow_replace", "0", { FCVAR_ARCHIVE }, "Autoriser le remplacement de la musique en cours (1=on)")

-- Binds utiles :
--   bind v car_radio_menu
--   bind b car_radio_stop
-- Admin (superadmin) :
--   !carradio   ou   car_radio_admin
