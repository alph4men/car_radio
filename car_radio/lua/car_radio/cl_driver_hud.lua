-- cl_driver_hud.lua — HUD fin & déplaçable + slider volume (conducteur uniquement)
if not CLIENT then return end

local function IsDriver()
    local lp = LocalPlayer()
    return IsValid(lp) and lp:InVehicle() and IsValid(lp:GetVehicle()) and lp:GetVehicle():GetDriver() == lp
end

-- position persistante (valeurs normalisées 0..1)
local function getPos()
    local nx = tonumber(cookie.GetString("car_radio_hud_x","0.5")) or 0.5
    local ny = tonumber(cookie.GetString("car_radio_hud_y","0.07")) or 0.07
    return math.Clamp(nx,0,1), math.Clamp(ny,0,1)
end
local function setPos(nx,ny)
    cookie.Set("car_radio_hud_x", tostring(math.Clamp(nx,0,1)))
    cookie.Set("car_radio_hud_y", tostring(math.Clamp(ny,0,1)))
end

-- taille & placement
local function SCALE() return math.Clamp(ScrW()/1920, 0.7, 1.25) end
local function BOX()
    local s=SCALE()
    local W = math.floor(340*s)
    local H = math.floor(46*s)
    local nx,ny = getPos()
    local x = math.floor(nx*ScrW() - W/2)
    local y = math.floor(ny*ScrH() - H/2)
    return x,y,W,H,s
end

surface.CreateFont("CR_HUD_Label", {font="Tahoma", size=16, weight=750})
surface.CreateFont("CR_HUD_Small", {font="Tahoma", size=13, weight=700})

-- état slider / drag
local dragging = false
local ui_gain = 1.0
local draggingHUD = false
local dragDX, dragDY = 0,0

-- lit le gain connu côté client
local function GetVehGain()
    local veh = LocalPlayer():GetVehicle()
    if not IsValid(veh) then return 1 end
    if isfunction(CAR_RADIO_GetVehicleGain) then
        local g = CAR_RADIO_GetVehicleGain(veh)
        if g == nil then return 1 end
        return math.Clamp(g, 0, 1)
    end
    return ui_gain
end

-- envoi serveur
local function SendGainToServer(g)
    local veh = LocalPlayer():GetVehicle()
    if not IsValid(veh) then return end
    net.Start("CAR_RADIO_SetGain")
        net.WriteEntity(veh)
        net.WriteFloat(math.Clamp(g or 1, 0, 1))
    net.SendToServer()
end

hook.Add("HUDPaint", "CAR_RADIO_HUD_DRAG", function()
    if not IsDriver() then return end

    local x,y,W,H,s = BOX()

    -- fond pill (zone draggable au clic droit)
    draw.RoundedBox(10, x, y, W, H, Color(12,14,18,210))
    surface.SetDrawColor(120,200,255,90)
    surface.DrawOutlinedRect(x, y, W, H, 1)

    local pad = math.floor(6*s)
    local bw  = math.floor(100*s)
    local bh  = H - pad*2

    local rPlay = {x=x+pad,           y=y+pad, w=bw, h=bh}
    local rStop = {x=x+pad+bw+pad,    y=y+pad, w=bw, h=bh}
    local rVol  = {x=x+W-pad-math.floor(120*s), y=y+pad, w=math.floor(120*s), h=bh}

    local mx,my = gui.MousePos()
    local function hit(r) return mx>=r.x and mx<=r.x+r.w and my>=r.y and my<=r.y+r.h end

    local function btn(r, label)
        local hov = hit(r)
        draw.RoundedBox(8, r.x, r.y, r.w, r.h, hov and Color(30,36,44,240) or Color(22,26,32,220))
        surface.SetDrawColor(120,200,255, hov and 200 or 120)
        surface.DrawOutlinedRect(r.x, r.y, r.w, r.h, 1)
        draw.SimpleText(label, "CR_HUD_Label", r.x+r.w/2, r.y+r.h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    btn(rPlay, "▶ Play")
    btn(rStop, "■ Stop")

    -- slider volume
    local g_srv = GetVehGain()
    if not dragging then ui_gain = g_srv end

    draw.RoundedBox(8, rVol.x, rVol.y, rVol.w, rVol.h, Color(18,20,26,220))
    surface.SetDrawColor(120,200,255,120)
    surface.DrawOutlinedRect(rVol.x, rVol.y, rVol.w, rVol.h, 1)

    local inner = math.floor(8*s)
    local tx = rVol.x + inner
    local tw = rVol.w - inner*2
    local ty = rVol.y + rVol.h/2

    surface.SetDrawColor(70,120,170,180)
    surface.DrawLine(tx, ty, tx+tw, ty)

    local knobX = tx + math.floor(tw * ui_gain)
    local r = math.floor(6*s)
    draw.RoundedBox(r, knobX-r, ty-r, r*2, r*2, Color(120,200,255,220))

    draw.SimpleText(tostring(math.floor(ui_gain*100)).."%", "CR_HUD_Small", rVol.x+4, rVol.y+2, Color(210,230,255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- drag du slider (gauche)
    local overVol = hit(rVol)
    if input.IsMouseDown(MOUSE_LEFT) and overVol and not draggingHUD then dragging = true end
    if not input.IsMouseDown(MOUSE_LEFT) and dragging then
        dragging = false
        SendGainToServer(ui_gain)
    end
    if dragging then
        local t = 0
        if tw > 0 then t = (mx - tx) / tw end
        ui_gain = math.Clamp(t, 0, 1)
    end

    -- drag du HUD (clic droit n'importe où dans la boîte)
    if input.IsMouseDown(MOUSE_RIGHT) then
        if not draggingHUD and mx>=x and mx<=x+W and my>=y and my<=y+H then
            draggingHUD = true
            dragDX = mx - x
            dragDY = my - y
        end
    else
        if draggingHUD then
            draggingHUD = false
            -- sauvegarde
            local nx = (x + W/2) / ScrW()
            local ny = (y + H/2) / ScrH()
            setPos(nx, ny)
        end
    end
    if draggingHUD then
        local nx = mx - dragDX
        local ny = my - dragDY
        -- clamp à l'écran
        nx = math.Clamp(nx, 0, ScrW()-W)
        ny = math.Clamp(ny, 0, ScrH()-H)
        -- rendu visuel en déplaçant “virtuellement” (pas besoin de stocker, BOX lit les cookies)
        draw.RoundedBox(0, nx, ny, W, H, Color(255,255,255,0)) -- juste pour forcer un repaint propre
        -- position temporaire pour cet instant : on triche en écrivant le cookie en continu (fluide)
        local nnx = (nx + W/2)/ScrW()
        local nny = (ny + H/2)/ScrH()
        setPos(nnx, nny)
    end
end)

hook.Add("GUIMousePressed", "CAR_RADIO_HUD_DRAG_Click", function(mc)
    if mc ~= MOUSE_LEFT or not IsDriver() then return end
    local mx,my = gui.MousePos(); if mx<=0 and my<=0 then return end
    local x,y,W,H,s = BOX()
    local pad = math.floor(6*s)
    local bw  = math.floor(100*s)
    local bh  = H - pad*2
    local rPlay = {x=x+pad, y=y+pad, w=bw, h=bh}
    local rStop = {x=x+pad+bw+pad, y=y+pad, w=bw, h=bh}
    local function hit(r) return mx>=r.x and mx<=r.x+r.w and my>=r.y and my<=r.y+r.h end

    if hit(rPlay) then
        if isfunction(CAR_RADIO_OpenMenu) then
            CAR_RADIO_OpenMenu(LocalPlayer():GetVehicle())
        else
            RunConsoleCommand("car_radio_menu")
        end
    elseif hit(rStop) then
        local veh = LocalPlayer():GetVehicle()
        if IsValid(veh) then
            net.Start("CAR_RADIO_RequestStop"); net.WriteEntity(veh); net.SendToServer()
        end
    end
end)

-- Reset position (optionnel)
concommand.Add("car_radio_hud_reset", function()
    setPos(0.5, 0.07)
    chat.AddText(Color(120,200,255),"[CarRadio] ", color_white, "Position HUD réinitialisée.")
end)
