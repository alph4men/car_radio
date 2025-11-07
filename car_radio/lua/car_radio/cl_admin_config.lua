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

    local fr = vgui.Create("DFrame")
    fr:SetSize(560, 620)
    fr:Center()
    fr:SetTitle("Car Radio — Configuration (superadmin)")
    fr:MakePopup()

    local sc = vgui.Create("DScrollPanel", fr)
    sc:Dock(FILL)
    sc:DockMargin(10, 10, 10, 10)

    local fields = {}

    local function addSlider(key, meta)
        local pnl = vgui.Create("DPanel", sc)
        pnl:Dock(TOP); pnl:SetTall(70); pnl:DockMargin(0,0,0,8)
        pnl.Paint = function(self,w,h) surface.SetDrawColor(15,15,18,180); surface.DrawRect(0,0,w,h) end

        local lab = vgui.Create("DLabel", pnl)
        lab:SetText((meta.label or key) .. string.format("  [%.2f → %.2f]", meta.min or 0, meta.max or 0))
        lab:Dock(TOP); lab:DockMargin(8,6,8,4)

        local sld = vgui.Create("DNumSlider", pnl)
        sld:Dock(TOP); sld:DockMargin(8,0,8,8)
        sld:SetMin(meta.min or 0); sld:SetMax(meta.max or 1)
        sld:SetDecimals(meta.type=="int" and 0 or 2)
        sld:SetValue(SNAP[key] or 0)
        sld:SetDark(true)

        fields[key] = function() return meta.type=="int" and math.floor(sld:GetValue()) or sld:GetValue() end
    end

    local function addCheckbox(key, meta)
        local pnl = vgui.Create("DPanel", sc)
        pnl:Dock(TOP); pnl:SetTall(46); pnl:DockMargin(0,0,0,8)
        pnl.Paint = function(self,w,h) surface.SetDrawColor(15,15,18,180); surface.DrawRect(0,0,w,h) end

        local cb = vgui.Create("DCheckBoxLabel", pnl)
        cb:Dock(LEFT); cb:DockMargin(8,10,0,0)
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
    row:Dock(BOTTOM); row:SetTall(50); row:DockMargin(10,0,10,10); row.Paint=nil

    local btnAuth = vgui.Create("DButton", row)
    btnAuth:Dock(LEFT); btnAuth:SetWide(180); btnAuth:SetText("Autorisations…")
    btnAuth.DoClick = function()
        net.Start("CAR_RADIO_AuthOpen"); net.SendToServer()
    end

    local btnApply = vgui.Create("DButton", row)
    btnApply:Dock(RIGHT); btnApply:SetWide(190); btnApply:SetText("Appliquer & Sauver")

    local btnClose = vgui.Create("DButton", row)
    btnClose:Dock(RIGHT); btnClose:SetWide(120); btnClose:DockMargin(0,0,8,0)
    btnClose:SetText("Fermer")
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

    local fr = vgui.Create("DFrame")
    fr:SetSize(640, 520)
    fr:Center()
    fr:SetTitle("Car Radio — Autorisations (superadmin)")
    fr:MakePopup()

    local top = vgui.Create("DPanel", fr)
    top:Dock(TOP); top:SetTall(70); top:DockMargin(10,10,10,0)
    top.Paint = function(self,w,h) surface.SetDrawColor(15,15,18,180); surface.DrawRect(0,0,w,h) end

    local cbAllowAll = vgui.Create("DCheckBoxLabel", top)
    cbAllowAll:Dock(LEFT); cbAllowAll:DockMargin(10,10,0,0)
    cbAllowAll:SetText("Autoriser tous les joueurs")
    cbAllowAll:SetValue(allow_all and 1 or 0)
    cbAllowAll:SetDark(true)

    local addRow = vgui.Create("DPanel", fr)
    addRow:Dock(TOP); addRow:SetTall(46); addRow:DockMargin(10,8,10,0)
    addRow.Paint = function(self,w,h) surface.SetDrawColor(15,15,18,180); surface.DrawRect(0,0,w,h) end

    local txtSID = vgui.Create("DTextEntry", addRow)
    txtSID:Dock(LEFT); txtSID:SetWide(240); txtSID:DockMargin(8,10,8,10)
    txtSID:SetPlaceholderText("SteamID64 (ex: 76561198000000000)")

    local cboOnline = vgui.Create("DComboBox", addRow)
    cboOnline:Dock(LEFT); cboOnline:SetWide(220); cboOnline:DockMargin(0,10,8,10)
    cboOnline:SetValue("Ajouter joueur connecté…")
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) then
            cboOnline:AddChoice(p:Nick().." ("..(p:SteamID64() or "?")..")", p:SteamID64() or "")
        end
    end
    function cboOnline:OnSelect(_, _, data)
        if data and data ~= "" then txtSID:SetText(data) end
    end

    local btnAdd = vgui.Create("DButton", addRow)
    btnAdd:Dock(LEFT); btnAdd:SetWide(120); btnAdd:SetText("Ajouter")
    btnAdd.DoClick = function()
        local sid = string.Trim(txtSID:GetText() or "")
        if sid == "" then return end
        -- Évite doublons
        for _, row in ipairs(LIST) do if row.sid == sid then return end end
        LIST[#LIST+1] = { sid = sid, label = sid }
        txtSID:SetText("")
        refreshList()
    end

    local sc = vgui.Create("DScrollPanel", fr)
    sc:Dock(FILL); sc:DockMargin(10,8,10,10)

    local function makeLine(idx, row)
        local pnl = vgui.Create("DPanel", sc)
        pnl:Dock(TOP); pnl:SetTall(36); pnl:DockMargin(0,0,0,6)
        pnl.Paint = function(self,w,h) surface.SetDrawColor(10,12,16,200); surface.DrawRect(0,0,w,h) end

        local lab = vgui.Create("DLabel", pnl)
        lab:Dock(LEFT); lab:SetWide(440); lab:DockMargin(8,8,0,0)
        lab:SetText(row.label or row.sid or "?")

        local btnDel = vgui.Create("DButton", pnl)
        btnDel:Dock(RIGHT); btnDel:SetWide(90); btnDel:SetText("Retirer")
        btnDel.DoClick = function()
            for i=#LIST,1,-1 do
                if LIST[i].sid == row.sid then table.remove(LIST,i) break end
            end
            refreshList()
        end
        return pnl
    end

    function refreshList()
        sc:Clear()
        table.sort(LIST, function(a,b) return (a.label or a.sid) < (b.label or b.sid) end)
        for i, row in ipairs(LIST) do
            makeLine(i, row)
        end
    end
    refreshList()

    local bottom = vgui.Create("DPanel", fr)
    bottom:Dock(BOTTOM); bottom:SetTall(50); bottom:DockMargin(10,0,10,10); bottom.Paint=nil

    local btnSave = vgui.Create("DButton", bottom)
    btnSave:Dock(RIGHT); btnSave:SetWide(200); btnSave:SetText("Sauver les autorisations")
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
    btnClose:Dock(RIGHT); btnClose:SetWide(120); btnClose:DockMargin(0,0,8,0)
    btnClose:SetText("Fermer")
    btnClose.DoClick = function() fr:Close() end
end)
