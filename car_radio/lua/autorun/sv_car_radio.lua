-- Wrapper autorun pour charger la version principale du script serveur.
if SERVER then
    CAR_RADIO = CAR_RADIO or {}
    if not CAR_RADIO.__server_core_loaded then
        include("car_radio/sv_car_radio.lua")
    end
end
