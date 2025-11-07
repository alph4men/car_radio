-- Wrapper autorun pour charger la version principale du script client.
if CLIENT then
    CAR_RADIO = CAR_RADIO or {}
    if not CAR_RADIO.__core_loaded then
        include("car_radio/cl_car_radio.lua")
    end
end
