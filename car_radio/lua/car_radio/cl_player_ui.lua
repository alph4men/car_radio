-- cl_player_ui.lua
if not CLIENT then return end

-- Fonction globale utilisée par HUD/console
function CAR_RADIO_OpenMenu(veh)
    if not IsValid(veh) then return end

    local fr = vgui.Create("DFrame")
    fr:SetSize(500, 190)
    fr:Center()
    fr:SetTitle("Car Radio - Lien YouTube")
    fr:MakePopup()

    local lab = vgui.Create("DLabel", fr)
    lab:SetText("Colle un lien YouTube (watch?v=... ou youtu.be/...)")
    lab:Dock(TOP)
    lab:DockMargin(10,10,10,5)

    local txt = vgui.Create("DTextEntry", fr)
    txt:Dock(TOP)
    txt:DockMargin(10,0,10,5)
    txt:SetPlaceholderText("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    txt:SetUpdateOnType(true)

    local hint = vgui.Create("DLabel", fr)
    hint:SetText("Astuce : bind une touche →  bind v car_radio_menu")
    hint:Dock(TOP)
    hint:DockMargin(10,0,10,10)

    local row = vgui.Create("Panel", fr)
    row:Dock(BOTTOM)
    row:SetTall(44)
    row:DockMargin(10,0,10,10)

    local btnPlay = vgui.Create("DButton", row)
    btnPlay:SetText("▶ Lancer")
    btnPlay:Dock(LEFT)
    btnPlay:SetWide(220)

    local btnStop = vgui.Create("DButton", row)
    btnStop:SetText("■ Stop")
    btnStop:Dock(RIGHT)
    btnStop:SetWide(220)

    btnPlay.DoClick = function()
        local url = string.Trim(txt:GetText() or "")
        if url == "" then
            chat.AddText(Color(255,100,100), "[CarRadio] ", color_white, "Merci de coller un lien.")
            return
        end
        net.Start("CAR_RADIO_RequestPlay")
            net.WriteEntity(veh)
            net.WriteString(url)
        net.SendToServer()
        fr:Close()
    end

    btnStop.DoClick = function()
        net.Start("CAR_RADIO_RequestStop")
            net.WriteEntity(veh)
        net.SendToServer()
        fr:Close()
    end
end
