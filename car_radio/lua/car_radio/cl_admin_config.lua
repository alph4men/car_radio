-- cl_admin_config.lua (UI admin superadmin + onglet Autorisations)
if not CLIENT then return end

-- ====== Réseau : confirmations ======
net.Receive("CAR_RADIO_ConfigSaved", function()
    chat.AddText(Color(120,200,255), "[CarRadio] ", color_white, "Configuration sauvegardée.")
end)

net.Receive("CAR_RADIO_AuthSaved", function()
    chat.AddText(Color(120,200,255), "[CarRadio] ", color_white, "Autorisations sauvegardées.")
end)

-- ====== UI CONFIG (ConVars) ======
local SCHEMA = {
    car_radio_radius             = { type="float", min=100,  max=5000, label="Rayon (units)" },
    car_radio_falloff            = { type="float", min=0.2,  max=4.0,  label="Décroissance (puissance)" },
    car_radio_allow_passengers   = { type="bool",  label="Passagers peuvent play/stop (ign. serveur)" },
    car_radio_sync_hz            = { type="float", min=0.2,  max=5.0,  label="Sync Hz (1 = 1/s)" },
    car_radio_player_cooldown    = { type="float", min=0.0,  max=60.0, label="Cooldown joueur (s)" },
    car_radio_vehicle_cooldown   = { type="float", min=0.0,  max=60.0, label="Cooldown véhicule (s)" },
    car_radio_url_maxlen         = { type="int",   min=32,   max=512,  label="URL max (car.)" },
    car_radio_max_active         = { type="int",   min=1,    max=200,  label="Radios max simultanées" },
    car_radio_cap_per_driver     = { type="bool",  label="Cap conducteur (1 voiture max)" },
    car_radio_allow_replace      = { type="bool",  label="Autoriser remplacement musique" },
}

local function MakeThemedFrame(width, height, title, subtitle)
    local fr = vgui.Create("DFrame")
    fr:SetSize(width, height)
    fr:Center()
    fr:SetTitle("")
    fr:SetSizable(false)
    fr:ShowCloseButton(false)
    fr:MakePopup()

    fr.Paint = function(self, w, h)
        draw.RoundedBox(16, 0, 0, w, h, Color(10, 12, 18, 240))
        surface.SetDrawColor(120, 200, 255, 110)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText(title or "", "Trebuchet24", 24, 34, Color(220, 235, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if subtitle and subtitle ~= "" then
            draw.SimpleText(subtitle, "Trebuchet18", 24, 62, Color(170, 190, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
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
        if IsValid(self.CloseButton) then
            self.CloseButton:SetPos(self:GetWide() - 44, 18)
        end
    end

    fr:DockPadding(20, 84, 20, 20)
    fr.CloseButton = close
    return fr
end

-- ====== Fenêtre principale (ConVars + bouton Autorisations...) ======
net.Receive("CAR_RADIO_ConfigSnapshot", function()
    local n = net.ReadUInt(8)
    local SNAP = {}
    for i=1, n do
        local key = net.ReadString()
        local meta = SCHEMA[key]
        if meta then
            if meta.type == "bool" then
                SNAP[key] = net.ReadBool()
            elseif meta.type == "int" then
                SNAP[key] = net.ReadInt(16)
            else
                SNAP[key] = net.ReadFloat()
            end
        else
            _ = net.ReadFloat()
        end
    end

    local fr = MakeThemedFrame(600, 640, "Car Radio — Configuration", "Ajuste les paramètres serveur en direct")

    local sc = vgui.Create("DScrollPanel", fr)
    sc:Dock(FILL)

    local fields = {}

    local function addSlider(key, meta)
        local pnl = vgui.Create("DPanel", sc)
        pnl:Dock(TOP); pnl:SetTall(76); pnl:DockMargin(0,0,0,10)
        pnl.Paint = function(_,w,h)
            draw.RoundedBox(12,0,0,w,h,Color(16,20,28,235))
            surface.SetDrawColor(80,140,210,100)
            surface.DrawOutlinedRect(0,0,w,h,1)
        end

        local lab = vgui.Create("DLabel", pnl)
        lab:SetText((meta.label or key) .. string.format("  [%.2f → %.2f]", meta.min or 0, meta.max or 0))
        lab:Dock(TOP); lab:DockMargin(12,8,12,6)
        lab:SetTextColor(Color(210,225,255))

        local sld = vgui.Create("DNumSlider", pnl)
        sld:Dock(TOP); sld:DockMargin(12,0,12,10)
        sld:SetMin(meta.min or 0); sld:SetMax(meta.max or 1)
        sld:SetDecimals(meta.type=="int" and 0 or 2)
        sld:SetValue(SNAP[key] or 0)
        sld:SetDark(true)

        fields[key] = function() return meta.type=="int" and math.floor(sld:GetValue()) or sld:GetValue() end
    end

    local function addCheckbox(key, meta)
        local pnl = vgui.Create("DPanel", sc)
        pnl:Dock(TOP); pnl:SetTall(56); pnl:DockMargin(0,0,0,10)
        pnl.Paint = function(_,w,h)
            draw.RoundedBox(12,0,0,w,h,Color(16,20,28,235))
            surface.SetDrawColor(80,140,210,100)
            surface.DrawOutlinedRect(0,0,w,h,1)
        end

        local cb = vgui.Create("DCheckBoxLabel", pnl)
        cb:Dock(LEFT); cb:DockMargin(12,12,0,0)
        cb:SetText(meta.label or key)
        cb:SetValue(SNAP[key] and 1 or 0)
        cb:SetDark(true)

        fields[key] = function() return cb:GetChecked() end
    end

    local order = {
        "car_radio_radius",
        "car_radio_falloff",
        "car_radio_allow_passengers",
        "car_radio_sync_hz",
        "car_radio_player_cooldown",
        "car_radio_vehicle_cooldown",
        "car_radio_url_maxlen",
        "car_radio_max_active",
        "car_radio_cap_per_driver",
        "car_radio_allow_replace",
    }

    for _, key in ipairs(order) do
        local meta = SCHEMA[key]
        if meta then
            if meta.type == "bool" then addCheckbox(key, meta) else addSlider(key, meta) end
        end
    end

    -- Barre de boutons bas
    local row = vgui.Create("DPanel", fr)
    row:Dock(BOTTOM); row:SetTall(58); row.Paint = nil

    local btnAuth = vgui.Create("DButton", row)
    btnAuth:Dock(LEFT); btnAuth:SetWide(200); btnAuth:SetText("")
    btnAuth.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(90,140,220) or Color(70,120,200))
        draw.SimpleText("Autorisations…", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnAuth.DoClick = function()
        net.Start("CAR_RADIO_AuthOpen"); net.SendToServer()
    end

    local btnApply = vgui.Create("DButton", row)
    btnApply:Dock(RIGHT); btnApply:SetWide(220); btnApply:SetText("")
    btnApply.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(70,150,100) or Color(60,130,90))
        draw.SimpleText("Appliquer & Sauver", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", row)
    btnClose:Dock(RIGHT); btnClose:SetWide(120); btnClose:DockMargin(12,0,12,0)
    btnClose:SetText("")
    btnClose.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(140,80,80) or Color(110,60,60))
        draw.SimpleText("Fermer", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnClose.DoClick = function() fr:Close() end

    btnApply.DoClick = function()
        local pack = {}
        for key, getter in pairs(fields) do
            local val = getter()
            local meta = SCHEMA[key]
            if meta then
                if meta.type == "bool" then
                    pack[key] = val and true or false
                elseif meta.type == "int" then
                    val = math.floor(val or 0)
                    if meta.min then val = math.max(meta.min, val) end
                    if meta.max then val = math.min(meta.max, val) end
                    pack[key] = val
                else
                    val = tonumber(val) or 0
                    if meta.min then val = math.max(meta.min, val) end
                    if meta.max then val = math.min(meta.max, val) end
                    pack[key] = val
                end
            end
        end

        net.Start("CAR_RADIO_ConfigApply")
            net.WriteUInt(table.Count(pack), 8)
            for key, val in pairs(pack) do
                local meta = SCHEMA[key]
                net.WriteString(key)
                if meta.type == "bool" then net.WriteBool(val)
                elseif meta.type == "int" then net.WriteInt(val, 16)
                else net.WriteFloat(val) end
            end
        net.SendToServer()
    end
end)

-- ====== UI Autorisations (Whitelist) ======
net.Receive("CAR_RADIO_AuthSnapshot", function()
    local allow_all = net.ReadBool()
    local n = net.ReadUInt(12)
    local LIST = {}
    for i=1,n do
        local sid = net.ReadString()
        local label = net.ReadString()
        LIST[#LIST+1] = { sid = sid, label = label }
    end

    local fr = MakeThemedFrame(640, 540, "Car Radio — Autorisations", "Gère la liste blanche des conducteurs")

    local top = vgui.Create("DPanel", fr)
    top:Dock(TOP); top:SetTall(74)
    top.Paint = function(_,w,h)
        draw.RoundedBox(12,0,0,w,h,Color(16,20,28,235))
        surface.SetDrawColor(80,140,210,100)
        surface.DrawOutlinedRect(0,0,w,h,1)
    end

    local cbAllowAll = vgui.Create("DCheckBoxLabel", top)
    cbAllowAll:Dock(LEFT); cbAllowAll:DockMargin(14,14,0,0)
    cbAllowAll:SetText("Autoriser tous les joueurs")
    cbAllowAll:SetValue(allow_all and 1 or 0)
    cbAllowAll:SetDark(true)

    local addRow = vgui.Create("DPanel", fr)
    addRow:Dock(TOP); addRow:SetTall(56); addRow:DockMargin(0,10,0,0)
    addRow.Paint = function(_,w,h)
        draw.RoundedBox(12,0,0,w,h,Color(16,20,28,235))
        surface.SetDrawColor(80,140,210,100)
        surface.DrawOutlinedRect(0,0,w,h,1)
    end

    local txtSID = vgui.Create("DTextEntry", addRow)
    txtSID:Dock(LEFT); txtSID:SetWide(260); txtSID:DockMargin(12,12,12,12)
    txtSID:SetPlaceholderText("SteamID64 (ex: 76561198000000000)")

    local cboOnline = vgui.Create("DComboBox", addRow)
    cboOnline:Dock(LEFT); cboOnline:SetWide(220); cboOnline:DockMargin(0,12,12,12)
    cboOnline:SetValue("Joueur connecté…")
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) then
            cboOnline:AddChoice(p:Nick() .. " (" .. (p:SteamID64() or "?") .. ")", p:SteamID64() or "")
        end
    end
    function cboOnline:OnSelect(_, _, data)
        if data and data ~= "" then txtSID:SetText(data) end
    end

    local btnAdd = vgui.Create("DButton", addRow)
    btnAdd:Dock(FILL)
    btnAdd:SetText("")
    btnAdd.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(70,150,100) or Color(60,130,90))
        draw.SimpleText("Ajouter", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local sc = vgui.Create("DScrollPanel", fr)
    sc:Dock(FILL); sc:DockMargin(0,10,0,0)

    local function refreshList()
        sc:Clear()
        table.sort(LIST, function(a,b) return (a.label or a.sid) < (b.label or b.sid) end)
        for _, row in ipairs(LIST) do
            local pnl = vgui.Create("DPanel", sc)
            pnl:Dock(TOP); pnl:SetTall(42); pnl:DockMargin(0,0,0,8)
            pnl.Paint = function(_,w,h)
                draw.RoundedBox(10,0,0,w,h,Color(12,14,20,215))
                surface.SetDrawColor(60,110,170,90)
                surface.DrawOutlinedRect(0,0,w,h,1)
            end

            local lab = vgui.Create("DLabel", pnl)
            lab:Dock(FILL); lab:DockMargin(12,0,0,0)
            lab:SetText(row.label or row.sid or "?")
            lab:SetTextColor(Color(210,225,255))
            lab:SetContentAlignment(4)

            local btnDel = vgui.Create("DButton", pnl)
            btnDel:Dock(RIGHT); btnDel:SetWide(110); btnDel:SetText("")
            btnDel.Paint = function(self,w,h)
                local hovered = self:IsHovered()
                draw.RoundedBox(10, 0, 0, w, h, hovered and Color(150,80,80) or Color(120,60,60))
                draw.SimpleText("Retirer", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            btnDel.DoClick = function()
                for i=#LIST,1,-1 do
                    if LIST[i].sid == row.sid then table.remove(LIST,i) break end
                end
                refreshList()
            end
        end
    end

    btnAdd.DoClick = function()
        local sid = string.Trim(txtSID:GetText() or "")
        if sid == "" then return end
        for _, row in ipairs(LIST) do if row.sid == sid then return end end
        LIST[#LIST+1] = { sid = sid, label = sid }
        txtSID:SetText("")
        refreshList()
    end

    refreshList()

    local bottom = vgui.Create("DPanel", fr)
    bottom:Dock(BOTTOM); bottom:SetTall(56); bottom.Paint = nil

    local btnSave = vgui.Create("DButton", bottom)
    btnSave:Dock(RIGHT); btnSave:SetWide(220); btnSave:SetText("")
    btnSave.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(70,150,100) or Color(60,130,90))
        draw.SimpleText("Sauver", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnSave.DoClick = function()
        net.Start("CAR_RADIO_AuthApply")
            net.WriteBool(cbAllowAll:GetChecked() and true or false)
            net.WriteUInt(#LIST, 12)
            for _, row in ipairs(LIST) do
                net.WriteString(row.sid)
            end
        net.SendToServer()
    end

    local btnClose = vgui.Create("DButton", bottom)
    btnClose:Dock(RIGHT); btnClose:SetWide(140); btnClose:DockMargin(12,0,12,0)
    btnClose:SetText("")
    btnClose.Paint = function(self,w,h)
        local hovered = self:IsHovered()
        draw.RoundedBox(12, 0, 0, w, h, hovered and Color(140,80,80) or Color(110,60,60))
        draw.SimpleText("Fermer", "Trebuchet18", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnClose.DoClick = function() fr:Close() end
end)
