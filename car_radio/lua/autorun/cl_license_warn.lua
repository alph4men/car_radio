-- cl_license_warn.lua — affiche un message rouge si la licence est invalide
if not CLIENT then return end

net.Receive("CAR_RADIO_LicenseWarn", function()
    local ip = net.ReadString() or "inconnue"
    local msg = string.format("[CAR RADIO] Licence non activée, merci de contacter le créateur et lui fournir l'adresse IP de votre serveur (%s)", ip)
    chat.AddText(Color(255,0,0), msg)
end)
