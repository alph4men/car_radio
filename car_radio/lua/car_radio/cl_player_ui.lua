-- cl_player_ui.lua
if not CLIENT then return end

-- Fonction globale utilisée par HUD/console
local LAST_URL_COOKIE = "car_radio_last_url"

local function prettyUnits(u)
    if not u or u <= 0 then return "?" end
    if u >= 1000 then
        return string.format("%.1f km", u / 1000)
    end
    return string.format("%d m", math.floor(u))
end

function CAR_RADIO_OpenMenu(veh)
    if not IsValid(veh) then return end

    local fr = vgui.Create("DFrame")
    fr:SetSize(520, 280)
    fr:Center()
    fr:MakePopup()
    fr:ShowCloseButton(false)
    fr:SetTitle("")
    fr:SetSizable(false)

    local title = "Car Radio"
    local subtitle = "Diffuse une vidéo YouTube autour de ton véhicule"

    fr.Paint = function(self, w, h)
        draw.RoundedBox(16, 0, 0, w, h, Color(10, 12, 18, 240))
        surface.SetDrawColor(120, 200, 255, 110)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText(title, "Trebuchet24", 22, 32, Color(220, 235, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(subtitle, "Trebuchet18", 22, 60, Color(170, 190, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", fr)
    close:SetText("✕")
    close:SetFont("Trebuchet18")
    close:SetSize(32, 32)
    close:SetPos(fr:GetWide() - 44, 18)
    close:SetTextColor(Color(220, 235, 255))
    close.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        draw.RoundedBox(10, 0, 0, w, h, hovered and Color(160, 60, 60) or Color(120, 50, 50))
        return true
    end
    close.DoClick = function() fr:Close() end

    function fr:PerformLayout(...)
        DFrame.PerformLayout(self, ...)
        if IsValid(close) then
            close:SetPos(self:GetWide() - 44, 18)
        end
    end

    fr:DockPadding(20, 80, 20, 20)

    local entryWrap = vgui.Create("DPanel", fr)
    entryWrap:Dock(TOP)
    entryWrap:SetTall(68)
    entryWrap:DockMargin(0, 0, 0, 12)
    entryWrap.Paint = function(_, w, h)
        draw.RoundedBox(12, 0, 0, w, h, Color(16, 20, 28, 235))
        surface.SetDrawColor(80, 140, 210, 120)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local entryLabel = vgui.Create("DLabel", entryWrap)
    entryLabel:Dock(TOP)
    entryLabel:DockMargin(12, 8, 12, 6)
    entryLabel:SetText("Lien YouTube (watch?v=… ou youtu.be/…)")
    entryLabel:SetTextColor(Color(210, 225, 255))

    local txt = vgui.Create("DTextEntry", entryWrap)
    txt:Dock(FILL)
    txt:DockMargin(12, 0, 12, 12)
    txt:SetPlaceholderText("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    txt:SetText(cookie.GetString(LAST_URL_COOKIE, ""))
    txt:SetUpdateOnType(true)

    local infoRow = vgui.Create("DLabel", fr)
    infoRow:Dock(TOP)
    infoRow:DockMargin(0, 0, 0, 10)
    local radiusCV = GetConVar("car_radio_radius")
    local radius = radiusCV and radiusCV:GetFloat() or 0
    local meters = radius * 0.01905 -- approx. units to meters
    infoRow:SetText(string.format("Portée actuelle : %.0f unités (~%s) | Astuce : bind v car_radio_menu", radius, prettyUnits(meters)))
    infoRow:SetTextColor(Color(170, 190, 220))

    local btnRow = vgui.Create("DPanel", fr)
    btnRow:Dock(BOTTOM)
    btnRow:SetTall(52)
    btnRow:DockMargin(0, 12, 0, 0)
    btnRow.Paint = function() end

    local function makeButton(text, col)
        local btn = vgui.Create("DButton", btnRow)
        btn:SetText("")
        btn:SetWide((fr:GetWide() - 52) / 2)
        btn:Dock(LEFT)
        btn:DockMargin(0, 0, 12, 0)
        btn.Paint = function(self, w, h)
            local hovered = self:IsHovered()
            local base = Color(col.r, col.g, col.b, hovered and 255 or 220)
        draw.RoundedBox(12, 0, 0, w, h, base)
        draw.SimpleText(text, "Trebuchet18", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
        return btn
    end

    local btnPlay = makeButton("▶ Lancer", Color(70, 140, 220))
    local btnStop = makeButton("■ Arrêter", Color(150, 70, 70))
    btnStop:Dock(RIGHT)
    btnStop:DockMargin(12, 0, 0, 0)

    btnPlay.DoClick = function()
        local url = string.Trim(txt:GetText() or "")
        if url == "" then
            chat.AddText(Color(255, 120, 120), "[CarRadio] ", color_white, "Merci de coller un lien YouTube.")
            return
        end
        cookie.Set(LAST_URL_COOKIE, url)
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
