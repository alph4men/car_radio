-- sv_car_radio_netfix.lua : enregistre les channels réseau indispensables
if not SERVER then return end
util.AddNetworkString("CAR_RADIO_RequestPlay")
util.AddNetworkString("CAR_RADIO_RequestStop")
util.AddNetworkString("CAR_RADIO_Play")
util.AddNetworkString("CAR_RADIO_Stop")
util.AddNetworkString("CAR_RADIO_SetGain") -- <- celui qui manque chez toi
