-- Philips Hue for Q-SYS: control Hue lights, rooms and zones, and read Hue switches and motion
-- sensors, through a Hue Bridge on the local network. Talks to the bridge's CLIP v1 API over HTTP,
-- polls for feedback, and pairs from the panel.
--
-- Made by YZ at the SmartSpaces programming department. Provided as-is, without warranty.
-- Copyright (c) 2026 YZ, SmartSpaces. MIT License: see LICENSE, or the plugin's About page.

-- Install via Tools > Design Resources > Import, then drag from the User tree.

PluginInfo = {
    Name = "Smart Spaces WI~Philips Hue",
    Version = "1.2.0",
    -- No version in the Id: Designer matches placed instances to the installed plugin by Id, so a
    -- stable Id lets a new version update a design in place instead of needing a re-drag.
    Id = "smartspaces.philips-hue",
    Description = "Philips Hue lights, rooms and zones through a Hue Bridge: on/off, brightness, colour temperature, hue/saturation, scenes, Hue switches and motion sensors, with pairing from the panel. MIT License.",
    Author = "Smart Spaces WI",
    ShowDebug = false,
}

function GetPrettyName()
    return "Philips Hue v" .. PluginInfo.Version
end

MAX_LIGHTS = 32
MAX_GROUPS = 16
MAX_SWITCHES = 16
MAX_MOTION = 8
SWITCH_BUTTONS = 4

-- Per-slot control fields. Shared by the controls, the layout and the runtime.
LIGHT_FIELDS = { "Id", "Name", "On", "Reach", "Bri", "Ct", "Hue", "Sat" }
GROUP_FIELDS = { "Id", "Name", "On", "Bri", "Scene" }
SWITCH_FIELDS = { "Id", "Name", "Batt", "Reach", "Event", "P1", "P2", "P3", "P4", "H1", "H2", "H3", "H4" }
MOTION_FIELDS = { "Id", "Name", "Presence", "Lux", "Temp", "Batt", "Reach" }

function LKey(i, field) return string.format("L%02d%s", i, field) end
function GKey(i, field) return string.format("G%02d%s", i, field) end
function SKey(i, field) return string.format("S%02d%s", i, field) end
function MKey(i, field) return string.format("M%02d%s", i, field) end

-- Human names for the pins (layout PrettyName). Slot numbers are two digits so the pin list sorts.
LIGHT_LABELS = { Id = "ID", Name = "Name", On = "On", Reach = "Reachable", Bri = "Brightness",
    Ct = "Color Temp", Hue = "Hue", Sat = "Saturation" }
GROUP_LABELS = { Id = "ID", Name = "Name", On = "On", Bri = "Brightness", Scene = "Scene" }
SWITCH_LABELS = { Id = "ID", Name = "Name", Batt = "Battery", Reach = "Reachable", Event = "Last Event",
    P1 = "Button 1 Press", P2 = "Button 2 Press", P3 = "Button 3 Press", P4 = "Button 4 Press",
    H1 = "Button 1 Hold", H2 = "Button 2 Hold", H3 = "Button 3 Hold", H4 = "Button 4 Hold" }
MOTION_LABELS = { Id = "ID", Name = "Name", Presence = "Presence", Lux = "Light Level", Temp = "Temperature",
    Batt = "Battery", Reach = "Reachable" }
GLOBAL_LABELS = { BridgeIP = "Bridge IP", AppKey = "App Key", Pair = "Pair", Refresh = "Refresh",
    AllOn = "All On", AllOff = "All Off", AllOnLights = "All On (Lights page)", AllOffLights = "All Off (Lights page)",
    AllOnGroups = "All On (Groups page)", AllOffGroups = "All Off (Groups page)",
    AllOnSensors = "All On (Sensors page)", AllOffSensors = "All Off (Sensors page)", Online = "Online", Status = "Status", BridgeLights = "Bridge Lights",
    BridgeGroups = "Bridge Rooms and Zones", BridgeSensors = "Bridge Switches and Sensors" }

function PrettyFor(name)
    local n, f = name:match("^L(%d%d)(%a+)$")
    if n and LIGHT_LABELS[f] then return "Light " .. n .. " " .. LIGHT_LABELS[f] end
    n, f = name:match("^G(%d%d)(%a+)$")
    if n and GROUP_LABELS[f] then return "Group " .. n .. " " .. GROUP_LABELS[f] end
    n, f = name:match("^S(%d%d)(%w+)$")
    if n and SWITCH_LABELS[f] then return "Switch " .. n .. " " .. SWITCH_LABELS[f] end
    n, f = name:match("^M(%d%d)(%w+)$")
    if n and MOTION_LABELS[f] then return "Motion " .. n .. " " .. MOTION_LABELS[f] end
    return GLOBAL_LABELS[name] or name
end

-- A property's value, or a default when Designer hasn't supplied props (or the property is absent).
function PropValue(props, name, default)
    local p = props and props[name]
    if p == nil or p.Value == nil then return default end
    return p.Value
end

-- Every page but About carries an All On / All Off pair at the top. A control has one place on
-- the panel, so each page has its own pair; Setup's pair is the one with pins.
PAGE_ALL_BUTTONS = {
    ["Lights"]             = { "AllOnLights",  "AllOffLights" },
    ["Groups"]             = { "AllOnGroups",  "AllOffGroups" },
    ["Switches & Sensors"] = { "AllOnSensors", "AllOffSensors" },
    ["Setup"]              = { "AllOn",        "AllOff" },
}

function PageNames(props)
    local pages = { "Lights" }
    if PropValue(props, "Group Count", 4) > 0 then table.insert(pages, "Groups") end
    if PropValue(props, "Switch Count", 4) + PropValue(props, "Motion Count", 2) > 0 then
        table.insert(pages, "Switches & Sensors")
    end
    table.insert(pages, "Setup")
    table.insert(pages, "About")
    return pages
end

function GetProperties()
    return {
        { Name = "Bridge IP",       Type = "string",  Value = "" },
        { Name = "App Key",         Type = "string",  Value = "" },
        { Name = "Use HTTPS",       Type = "boolean", Value = false },
        { Name = "Light Count",     Type = "integer", Min = 1, Max = MAX_LIGHTS, Value = 8 },
        { Name = "Group Count",     Type = "integer", Min = 0, Max = MAX_GROUPS, Value = 4 },
        { Name = "Switch Count",    Type = "integer", Min = 0, Max = MAX_SWITCHES, Value = 4 },
        { Name = "Motion Count",    Type = "integer", Min = 0, Max = MAX_MOTION, Value = 2 },
        { Name = "Poll Interval",   Type = "integer", Min = 1, Max = 60, Value = 3 },
        { Name = "Transition Time", Type = "integer", Min = 0, Max = 50, Value = 4 },
    }
end

function RectifyProperties(props)
    return props
end

function GetControls(props)
    local ctls = {}
    local nl = PropValue(props, "Light Count", 8)
    local ng = PropValue(props, "Group Count", 4)

    for i = 1, nl do
        table.insert(ctls, { Name = LKey(i, "Id"),    ControlType = "Text" })
        table.insert(ctls, { Name = LKey(i, "Name"),  ControlType = "Text", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "On"),    ControlType = "Button", ButtonType = "Toggle", PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "Reach"), ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "Bri"),   ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "Ct"),    ControlType = "Knob", ControlUnit = "Integer", Min = 2000, Max = 6500, PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "Hue"),   ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 360, PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = LKey(i, "Sat"),   ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = "Both", UserPin = true })
    end

    for i = 1, ng do
        table.insert(ctls, { Name = GKey(i, "Id"),    ControlType = "Text" })
        table.insert(ctls, { Name = GKey(i, "Name"),  ControlType = "Text", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = GKey(i, "On"),    ControlType = "Button", ButtonType = "Toggle", PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = GKey(i, "Bri"),   ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = "Both", UserPin = true })
        table.insert(ctls, { Name = GKey(i, "Scene"), ControlType = "Text", PinStyle = "Both", UserPin = true })
    end

    for i = 1, PropValue(props, "Switch Count", 4) do
        table.insert(ctls, { Name = SKey(i, "Id"),    ControlType = "Text" })
        table.insert(ctls, { Name = SKey(i, "Name"),  ControlType = "Text", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = SKey(i, "Batt"),  ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = SKey(i, "Reach"), ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = SKey(i, "Event"), ControlType = "Text", PinStyle = "Output", UserPin = true })
        for b = 1, SWITCH_BUTTONS do
            table.insert(ctls, { Name = SKey(i, "P" .. b), ControlType = "Button", ButtonType = "Trigger", PinStyle = "Output", UserPin = true })
            table.insert(ctls, { Name = SKey(i, "H" .. b), ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
        end
    end

    for i = 1, PropValue(props, "Motion Count", 2) do
        table.insert(ctls, { Name = MKey(i, "Id"),       ControlType = "Text" })
        table.insert(ctls, { Name = MKey(i, "Name"),     ControlType = "Text", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = MKey(i, "Presence"), ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = MKey(i, "Lux"),      ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 100000, PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = MKey(i, "Temp"),     ControlType = "Knob", ControlUnit = "Float", Min = -40, Max = 100, PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = MKey(i, "Batt"),     ControlType = "Knob", ControlUnit = "Percent", Min = 0, Max = 100, PinStyle = "Output", UserPin = true })
        table.insert(ctls, { Name = MKey(i, "Reach"),    ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
    end

    table.insert(ctls, { Name = "BridgeIP",     ControlType = "Text" })
    table.insert(ctls, { Name = "AppKey",       ControlType = "Text" })
    table.insert(ctls, { Name = "Pair",         ControlType = "Button", ButtonType = "Trigger" })
    table.insert(ctls, { Name = "Refresh",      ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input", UserPin = true })
    table.insert(ctls, { Name = "AllOn",        ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input", UserPin = true })
    table.insert(ctls, { Name = "AllOff",       ControlType = "Button", ButtonType = "Trigger", PinStyle = "Input", UserPin = true })
    for _, page in ipairs(PageNames(props)) do
        local pair = PAGE_ALL_BUTTONS[page]
        if pair and page ~= "Setup" then
            table.insert(ctls, { Name = pair[1], ControlType = "Button", ButtonType = "Trigger" })
            table.insert(ctls, { Name = pair[2], ControlType = "Button", ButtonType = "Trigger" })
        end
    end
    table.insert(ctls, { Name = "Online",       ControlType = "Indicator", IndicatorType = "Led", PinStyle = "Output", UserPin = true })
    table.insert(ctls, { Name = "Status",       ControlType = "Text", PinStyle = "Output", UserPin = true })
    table.insert(ctls, { Name = "BridgeLights", ControlType = "Text" })
    table.insert(ctls, { Name = "BridgeGroups", ControlType = "Text" })
    table.insert(ctls, { Name = "BridgeSensors", ControlType = "Text" })

    return ctls
end

function GetPages(props)
    local pages = {}
    for _, name in ipairs(PageNames(props)) do table.insert(pages, { name = name }) end
    return pages
end

local UI = {
    Panel   = { 40, 40, 40 },
    Stroke  = { 20, 20, 20 },
    Title   = { 235, 235, 235 },
    Readout = { 200, 200, 200 },
    Dim     = { 160, 160, 160 },
    Btn     = { 70, 110, 150 },
    BtnOff  = { 60, 60, 60 },
    Outline = { 95, 95, 95 },
    White   = { 255, 255, 255 },
    Green   = { 0, 200, 0 },
    LedOff  = { 60, 60, 60 },
}

-- Layout helpers, declared above every caller.
local function background(graphics, w)
    table.insert(graphics, {
        Type = "GroupBox", Position = { 0, 0 }, Size = { w, 1 },
        Fill = UI.Panel, CornerRadius = 0, StrokeColor = UI.Stroke, StrokeWidth = 1,
    })
end

local function title(graphics, text, pad, w)
    table.insert(graphics, {
        Type = "Label", Text = text, Position = { pad, 6 }, Size = { w - 2 * pad, 20 },
        Color = UI.Title, FontSize = 13, IsBold = true, HTextAlign = "Center",
    })
end

local function header(graphics, text, x, y, w, align)
    table.insert(graphics, {
        Type = "Label", Text = text, Position = { x, y }, Size = { w, 16 },
        Color = UI.Dim, FontSize = 9, IsBold = true, HTextAlign = align or "Left",
    })
end

-- An editable field: light text on the dark panel inside an unfilled outline.
local function editField(layout, graphics, name, x, y, w, h, align)
    table.insert(graphics, {
        Type = "GroupBox", Position = { x, y }, Size = { w, h },
        CornerRadius = 2, StrokeColor = UI.Outline, StrokeWidth = 1,
    })
    layout[name] = {
        Style = "Text", Position = { x + 3, y + 1 }, Size = { w - 6, h - 2 },
        FontSize = 10, TextColor = UI.Title, TextBoxStyle = "NoBackground",
        HTextAlign = align or "Center", VTextAlign = "Center",
    }
end

local function readout(layout, name, x, y, w, h, align)
    layout[name] = {
        Style = "Text", IsReadOnly = true, Position = { x, y }, Size = { w, h },
        FontSize = 10, TextColor = UI.Readout, TextBoxStyle = "NoBackground",
        HTextAlign = align or "Left", VTextAlign = "Center",
    }
end

local function toggle(layout, name, x, y, w, h)
    layout[name] = {
        Style = "Button", ButtonStyle = "Toggle", Legend = "OFF", Position = { x, y }, Size = { w, h },
        FontSize = 10, IsBold = true, Color = UI.Btn, OffColor = UI.BtnOff, UnlinkOffColor = true,
        TextColor = UI.White, HTextAlign = "Center",
    }
end

local function trigger(layout, name, legend, x, y, w, h)
    layout[name] = {
        Style = "Button", ButtonStyle = "Trigger", Legend = legend, Position = { x, y }, Size = { w, h },
        FontSize = 11, IsBold = true, Colors = { UI.Btn, UI.Btn }, TextColor = UI.White,
        HTextAlign = "Center",
    }
end

local function led(layout, name, x, y)
    layout[name] = {
        Style = "Led", Position = { x, y }, Size = { 12, 12 }, CornerRadius = 6,
        Color = UI.Green, OffColor = UI.LedOff, UnlinkOffColor = true,
    }
end

local function fader(layout, name, x, y, w, h)
    layout[name] = { Style = "Fader", Position = { x, y }, Size = { w, h } }
end

-- Lay out columns left to right with a fixed gap; returns the columns (with x set) and the panel width.
local function columns(pad, gap, cols)
    local x = pad
    for _, c in ipairs(cols) do
        c.x = x
        x = x + c.w + gap
    end
    return cols, x - gap + pad
end

local function lightsLayout(props)
    local layout, graphics = {}, {}
    local n = PropValue(props, "Light Count", 8)
    local pad, gap = 8, 8
    local cols, panel_w = columns(pad, gap, {
        { key = "Id",    head = "ID",          w = 36 },
        { key = "Name",  head = "NAME",        w = 160 },
        { key = "On",    head = "",            w = 44 },
        { key = "Reach", head = "REACH",       w = 40 },
        { key = "Bri",   head = "BRIGHTNESS",  w = 150 },
        { key = "Ct",    head = "COLOR TEMP K", w = 130 },
        { key = "Hue",   head = "HUE",         w = 130 },
        { key = "Sat",   head = "SAT",         w = 110 },
    })
    local row_h, row_step = 20, 26

    background(graphics, panel_w)
    title(graphics, "PHILIPS HUE - LIGHTS", pad, panel_w)

    local head_y = 34
    for _, c in ipairs(cols) do
        header(graphics, c.head, c.x, head_y, c.w, (c.key == "Name") and "Left" or "Center")
    end

    local top = head_y + 20
    for i = 1, n do
        local y = top + (i - 1) * row_step
        for _, c in ipairs(cols) do
            local name = LKey(i, c.key)
            if c.key == "Id" then editField(layout, graphics, name, c.x, y, c.w, row_h)
            elseif c.key == "Name" then readout(layout, name, c.x, y, c.w, row_h)
            elseif c.key == "On" then toggle(layout, name, c.x, y, c.w, row_h)
            elseif c.key == "Reach" then led(layout, name, c.x + math.floor((c.w - 12) / 2), y + 4)
            else fader(layout, name, c.x, y, c.w, row_h) end
        end
    end

    graphics[1].Size = { panel_w, top + n * row_step + pad }
    return layout, graphics
end

local function groupsLayout(props)
    local layout, graphics = {}, {}
    local n = PropValue(props, "Group Count", 4)
    local pad, gap = 8, 8
    local cols, panel_w = columns(pad, gap, {
        { key = "Id",    head = "ID",         w = 36 },
        { key = "Name",  head = "ROOM / ZONE", w = 160 },
        { key = "On",    head = "",           w = 44 },
        { key = "Bri",   head = "BRIGHTNESS", w = 150 },
        { key = "Scene", head = "SCENE",      w = 200 },
    })
    local row_h, row_step = 20, 26

    background(graphics, panel_w)
    title(graphics, "PHILIPS HUE - ROOMS & ZONES", pad, panel_w)

    local head_y = 34
    for _, c in ipairs(cols) do
        header(graphics, c.head, c.x, head_y, c.w, (c.key == "Name" or c.key == "Scene") and "Left" or "Center")
    end

    local top = head_y + 20
    for i = 1, n do
        local y = top + (i - 1) * row_step
        for _, c in ipairs(cols) do
            local name = GKey(i, c.key)
            if c.key == "Id" then editField(layout, graphics, name, c.x, y, c.w, row_h)
            elseif c.key == "Name" then readout(layout, name, c.x, y, c.w, row_h)
            elseif c.key == "On" then toggle(layout, name, c.x, y, c.w, row_h)
            elseif c.key == "Bri" then fader(layout, name, c.x, y, c.w, row_h)
            else layout[name] = { Style = "ComboBox", Position = { c.x, y }, Size = { c.w, row_h }, FontSize = 10 } end
        end
    end

    graphics[1].Size = { panel_w, top + n * row_step + pad }
    return layout, graphics
end

local function setupLayout(props)
    local layout, graphics = {}, {}
    local pad = 8
    local label_w = 80
    local field_x = pad + label_w + 8
    local list_w = 210
    local panel_w = pad + 3 * list_w + 2 * 16 + pad
    local field_w = panel_w - field_x - pad - 104

    background(graphics, panel_w)
    title(graphics, "PHILIPS HUE - SETUP", pad, panel_w)

    header(graphics, "BRIDGE", pad, 34, panel_w - 2 * pad)

    local y1 = 56
    header(graphics, "Bridge IP", pad, y1 + 2, label_w)
    editField(layout, graphics, "BridgeIP", field_x, y1, field_w, 20, "Left")
    trigger(layout, "Refresh", "Refresh", panel_w - pad - 96, y1 - 2, 96, 24)

    local y2 = y1 + 28
    header(graphics, "App Key", pad, y2 + 2, label_w)
    editField(layout, graphics, "AppKey", field_x, y2, field_w, 20, "Left")
    trigger(layout, "Pair", "Pair", panel_w - pad - 96, y2 - 2, 96, 24)

    local y3 = y2 + 32
    led(layout, "Online", pad, y3 + 4)
    header(graphics, "ONLINE", pad + 18, y3 + 2, 52)
    readout(layout, "Status", pad + 74, y3, panel_w - 2 * pad - 74, 20)

    local y4 = y3 + 36
    header(graphics, "LIGHTS ON THE BRIDGE", pad, y4, list_w)
    header(graphics, "ROOMS & ZONES ON THE BRIDGE", pad + list_w + 16, y4, list_w)
    header(graphics, "SWITCHES & SENSORS ON THE BRIDGE", pad + 2 * (list_w + 16), y4, list_w)
    local list_h = 220
    layout["BridgeLights"] = { Style = "ListBox", Position = { pad, y4 + 20 }, Size = { list_w, list_h }, FontSize = 10 }
    layout["BridgeGroups"] = { Style = "ListBox", Position = { pad + list_w + 16, y4 + 20 }, Size = { list_w, list_h }, FontSize = 10 }
    layout["BridgeSensors"] = { Style = "ListBox", Position = { pad + 2 * (list_w + 16), y4 + 20 }, Size = { list_w, list_h }, FontSize = 10 }

    graphics[1].Size = { panel_w, y4 + 20 + list_h + pad }
    return layout, graphics
end

-- Switches (rows of ID, name, battery, reachable, 4 x press/hold, last event) above motion sensors
-- (ID, name, presence, light level, temperature, battery, reachable). Either section is left out
-- when its count is 0.
local function sensorsLayout(props)
    local layout, graphics = {}, {}
    local ns = PropValue(props, "Switch Count", 4)
    local nm = PropValue(props, "Motion Count", 2)
    local pad, row_h, row_step = 8, 20, 26
    local x_id, x_name, w_name = pad, pad + 44, 150
    local panel_w = 706

    background(graphics, panel_w)
    title(graphics, "PHILIPS HUE - SWITCHES & SENSORS", pad, panel_w)
    local y = 34

    if ns > 0 then
        header(graphics, "SWITCHES", pad, y, 200)
        local hy = y + 20
        local x_batt, x_reach, x_btn, btn_step, x_event = 210, 262, 310, 52, 518
        header(graphics, "ID", x_id, hy, 36, "Center")
        header(graphics, "NAME", x_name, hy, w_name)
        header(graphics, "BATT", x_batt, hy, 44, "Center")
        header(graphics, "REACH", x_reach, hy, 40, "Center")
        header(graphics, "BUTTONS: PRESS / HOLD", x_btn, hy, SWITCH_BUTTONS * btn_step, "Left")
        header(graphics, "LAST EVENT", x_event, hy, 180)
        local top = hy + 20
        for i = 1, ns do
            local ry = top + (i - 1) * row_step
            editField(layout, graphics, SKey(i, "Id"), x_id, ry, 36, row_h)
            readout(layout, SKey(i, "Name"), x_name, ry, w_name, row_h)
            readout(layout, SKey(i, "Batt"), x_batt, ry, 44, row_h, "Center")
            led(layout, SKey(i, "Reach"), x_reach + 14, ry + 4)
            for b = 1, SWITCH_BUTTONS do
                local bx = x_btn + (b - 1) * btn_step
                trigger(layout, SKey(i, "P" .. b), tostring(b), bx, ry, 26, row_h)
                led(layout, SKey(i, "H" .. b), bx + 30, ry + 4)
            end
            readout(layout, SKey(i, "Event"), x_event, ry, 180, row_h)
        end
        y = top + ns * row_step + 12
    end

    if nm > 0 then
        header(graphics, "MOTION SENSORS", pad, y, 200)
        local hy = y + 20
        local x_pres, x_lux, x_temp, x_batt, x_reach = 210, 282, 370, 448, 500
        header(graphics, "ID", x_id, hy, 36, "Center")
        header(graphics, "NAME", x_name, hy, w_name)
        header(graphics, "PRESENCE", x_pres, hy, 64, "Center")
        header(graphics, "LIGHT LUX", x_lux, hy, 80, "Center")
        header(graphics, "TEMP C", x_temp, hy, 70, "Center")
        header(graphics, "BATT", x_batt, hy, 44, "Center")
        header(graphics, "REACH", x_reach, hy, 40, "Center")
        local top = hy + 20
        for i = 1, nm do
            local ry = top + (i - 1) * row_step
            editField(layout, graphics, MKey(i, "Id"), x_id, ry, 36, row_h)
            readout(layout, MKey(i, "Name"), x_name, ry, w_name, row_h)
            led(layout, MKey(i, "Presence"), x_pres + 26, ry + 4)
            readout(layout, MKey(i, "Lux"), x_lux, ry, 80, row_h, "Center")
            readout(layout, MKey(i, "Temp"), x_temp, ry, 70, row_h, "Center")
            readout(layout, MKey(i, "Batt"), x_batt, ry, 44, row_h, "Center")
            led(layout, MKey(i, "Reach"), x_reach + 14, ry + 4)
        end
        y = top + nm * row_step + 12
    end

    graphics[1].Size = { panel_w, math.max(y, 120) }
    return layout, graphics
end

-- The SmartSpaces logo on a white card (PNG, base64), so it reads on either Designer theme.
ABOUT_LOGO = "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"

local function aboutLayout(props)
    local layout, graphics = {}, {}
    local pad, panel_w = 8, 520
    background(graphics, panel_w)
    title(graphics, "PHILIPS HUE FOR Q-SYS", pad, panel_w)
    local logo_w, logo_h = 232, 116
    table.insert(graphics, {
        Type = "Image", Image = ABOUT_LOGO,
        Position = { math.floor((panel_w - logo_w) / 2), 36 }, Size = { logo_w, logo_h },
    })
    local lines = {
        { "Version " .. PluginInfo.Version, true },
        { "Made by YZ at the SmartSpaces programming department.", false },
        { "", false },
        { "Provided as-is, without warranty of any kind.", false },
        { "MIT License: free to use, change and share, as long as the", false },
        { "copyright notice and licence text stay with it.", false },
        { "Copyright (c) 2026 YZ, SmartSpaces", false },
        { "", false },
        { "github.com/Yara162/Q-SYS-Philips-Hue", false },
        { "", false },
        { "Philips Hue is a trademark of Signify. This plugin is not made,", false },
        { "endorsed or supported by Signify.", false },
    }
    local y = 36 + logo_h + 14
    for _, line in ipairs(lines) do
        table.insert(graphics, {
            Type = "Label", Text = line[1], Position = { pad, y }, Size = { panel_w - 2 * pad, 16 },
            Color = line[2] and UI.Title or UI.Readout, FontSize = line[2] and 12 or 10, IsBold = line[2],
            HTextAlign = "Center",
        })
        y = y + 18
    end
    graphics[1].Size = { panel_w, y + pad }
    return layout, graphics
end

function GetControlLayout(props)
    local page_index = props["page_index"] and props["page_index"].Value or 1
    local page = PageNames(props)[page_index]
    local layout, graphics
    if page == "Groups" then layout, graphics = groupsLayout(props)
    elseif page == "Switches & Sensors" then layout, graphics = sensorsLayout(props)
    elseif page == "Setup" then layout, graphics = setupLayout(props)
    elseif page == "About" then layout, graphics = aboutLayout(props)
    else layout, graphics = lightsLayout(props) end
    local pair = PAGE_ALL_BUTTONS[page]
    if pair then
        local w = graphics[1].Size[1]
        trigger(layout, pair[1], "All On", w - 8 - 2 * 72 - 6, 4, 72, 24)
        trigger(layout, pair[2], "All Off", w - 8 - 72, 4, 72, 24)
    end
    for name, entry in pairs(layout) do entry.PrettyName = PrettyFor(name) end
    return layout, graphics
end

-- ============================================================================ runtime
if Controls then
    rj = require("rapidjson")

    NL = Properties["Light Count"].Value
    NG = Properties["Group Count"].Value
    NS = Properties["Switch Count"].Value
    NM = Properties["Motion Count"].Value
    POLL_S = Properties["Poll Interval"].Value
    TRANSITION = Properties["Transition Time"].Value
    USE_HTTPS = Properties["Use HTTPS"].Value

    HOLD_S = 3           -- polls leave a slot alone this long after a change to it
    POLL_GATE_S = 15     -- a poll with no answer after this long is abandoned
    STICKY_S = 10        -- how long an error stays on the Status line
    PAIR_WINDOW_S = 30
    GROUP_GAP_S = 1      -- Hue: about one group command per second
    SCENE_EVERY = math.max(1, math.floor(60 / POLL_S))
    SENSOR_POLL_S = 0.5  -- switches and motion sensors
    HOLD_EXPIRE_S = 3    -- a Hold LED clears itself this long after the last hold event
    SEND_TICK_S = 0.125  -- one command per tick: 8/s, leaving room for the polls in Hue's ~10/s

    -- Bridge data from the last good poll, keyed by the bridge's id strings.
    bridgeLights, bridgeGroups = {}, {}
    scenes = {}          -- group id -> { names = {...}, ids = { name -> scene id } }
    holdL, holdG = {}, {}
    pendingOrder, pendingBody = {}, {}
    lastGroupSend = -1000
    pollBusy, pollStarted, pollCount = false, 0, 0
    pollGen = 0          -- bumped when the IP or key changes; answers from an older generation are dropped
    wasOnline = false
    statusUntil = 0
    pairing, pairDeadline = false, 0
    bridgeSensors = {}
    sensorBusy, sensorStarted = false, 0
    switchSeen = {}      -- slot -> { id, key } of the last event seen; nil until the first sighting
    holdSeen = {}        -- slot -> { [button] = time of its last hold event }
    for i = 1, NS do holdSeen[i] = {} end

    local function L(i, field) return Controls[LKey(i, field)] end
    local function G(i, field) return Controls[GKey(i, field)] end

    local function now() return Timer.Now() end

    local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

    -- Round to a Lua integer: the bridge rejects 100.0 where it wants 100.
    local function round(x)
        local r = math.floor(x + 0.5)
        return math.tointeger(r) or r
    end

    local function clamp(x, lo, hi)
        if x < lo then return lo end
        if x > hi then return hi end
        return x
    end

    -- A slot's ID field: "" is empty (auto-fill takes it), "-" is kept blank on purpose.
    -- idOf gives the bridge ID or "" for both.
    UNUSED = "-"
    local function rawId(field) return trim(field.String) end
    local function idOf(field)
        local id = rawId(field)
        if id == UNUSED then return "" end
        return id
    end

    -- A toggle's state and caption together: the layout's Legend is fixed, so the runtime writes it.
    local function showOn(ctl, on)
        ctl.Boolean = on
        ctl.Legend = on and "ON" or "OFF"
    end

    local function bridgeIP() return trim(Controls.BridgeIP.String) end
    local function appKey() return trim(Controls.AppKey.String) end
    local function baseUrl() return (USE_HTTPS and "https://" or "http://") .. bridgeIP() end
    local function apiUrl(path) return baseUrl() .. "/api/" .. appKey() .. path end

    -- Status line. A sticky message (an error) holds for STICKY_S against routine messages;
    -- routine messages also stay off it while pairing runs.
    local function setStatus(msg, sticky)
        if sticky then
            statusUntil = now() + STICKY_S
        elseif now() < statusUntil or pairing then
            return
        end
        Controls.Status.String = msg
    end

    local function setOnline(on)
        Controls.Online.Boolean = on
        if not on then wasOnline = false end
    end

    local function decode(data)
        if type(data) ~= "string" or data == "" then return nil end
        local ok, t = pcall(rj.decode, data)
        if ok and type(t) == "table" then return t end
        return nil
    end

    -- The first { error = {...} } in a v1 response array, or nil.
    local function hueError(t)
        if type(t) ~= "table" then return nil end
        for _, item in ipairs(t) do
            if type(item) == "table" and type(item.error) == "table" then return item.error end
        end
        return nil
    end

    local function request(method, url, body, callback)
        local args = {
            Url = url,
            Timeout = 5,
            Headers = { ["Content-Type"] = "application/json" },
            EventHandler = function(tbl, code, data, err) callback(code, data, err) end,
        }
        if method == "GET" then
            HttpClient.Get(args)
        else
            args.Method = method
            args.Data = body and rj.encode(body) or ""
            HttpClient.Upload(args)
        end
    end

    local function numericSort(ids)
        table.sort(ids, function(a, b)
            local na, nb = tonumber(a), tonumber(b)
            if na and nb and na ~= nb then return na < nb end
            return a < b
        end)
        return ids
    end

    local function lightIds()
        local ids = {}
        for id, v in pairs(bridgeLights) do if type(v) == "table" then table.insert(ids, id) end end
        return numericSort(ids)
    end

    local function isRoomOrZone(g) return g.type == "Room" or g.type == "Zone" end

    local function groupIds()
        local ids = {}
        for id, v in pairs(bridgeGroups) do if type(v) == "table" and isRoomOrZone(v) then table.insert(ids, id) end end
        return numericSort(ids)
    end

    -- ------------------------------------------------------------ feedback
    local function applyLight(i)
        local id = idOf(L(i, "Id"))
        local d = id ~= "" and bridgeLights[id] or nil
        if id == "" then
            L(i, "Name").String = ""
            L(i, "Reach").Boolean = false
            return
        end
        if type(d) ~= "table" then
            L(i, "Name").String = "(no light " .. id .. " on the bridge)"
            L(i, "Reach").Boolean = false
            return
        end
        L(i, "Name").String = d.name or ""
        local s = type(d.state) == "table" and d.state or {}
        L(i, "Reach").Boolean = s.reachable == true
        if holdL[i] and now() < holdL[i] then return end
        showOn(L(i, "On"), s.on == true)
        if type(s.bri) == "number" then L(i, "Bri").Value = round(s.bri / 254 * 100) end
        if type(s.ct) == "number" and s.ct > 0 then L(i, "Ct").Value = clamp(round(1e6 / s.ct), 2000, 6500) end
        if type(s.hue) == "number" then L(i, "Hue").Value = round(s.hue / 65535 * 360) end
        if type(s.sat) == "number" then L(i, "Sat").Value = round(s.sat / 254 * 100) end
    end

    local function applySceneChoices(i)
        local sc = scenes[idOf(G(i, "Id"))]
        G(i, "Scene").Choices = sc and sc.names or {}
    end

    local function applyGroup(i)
        local id = idOf(G(i, "Id"))
        local d = id ~= "" and bridgeGroups[id] or nil
        applySceneChoices(i)
        if id == "" then
            G(i, "Name").String = ""
            return
        end
        if type(d) ~= "table" then
            G(i, "Name").String = "(no group " .. id .. " on the bridge)"
            return
        end
        G(i, "Name").String = d.name or ""
        if holdG[i] and now() < holdG[i] then return end
        local s = type(d.state) == "table" and d.state or {}
        local a = type(d.action) == "table" and d.action or {}
        showOn(G(i, "On"), s.any_on == true)
        if type(a.bri) == "number" then G(i, "Bri").Value = round(a.bri / 254 * 100) end
    end

    local function applyAll()
        for i = 1, NL do applyLight(i) end
        for i = 1, NG do applyGroup(i) end
    end

    local function updateLists()
        local lines = {}
        for _, id in ipairs(lightIds()) do table.insert(lines, id .. "  " .. (bridgeLights[id].name or "")) end
        Controls.BridgeLights.Choices = lines
        lines = {}
        for _, id in ipairs(groupIds()) do
            local g = bridgeGroups[id]
            table.insert(lines, id .. "  " .. (g.name or "") .. "  (" .. g.type .. ")")
        end
        Controls.BridgeGroups.Choices = lines
    end

    -- Fill every empty slot, top down, with the bridge's IDs not already in a slot. A slot holding
    -- "-" is left alone, so a slot can be kept blank.
    local function fillSlots(n, idField, ids)
        local used = {}
        for i = 1, n do used[rawId(idField(i))] = true end
        local k = 1
        for i = 1, n do
            if rawId(idField(i)) == "" then
                while k <= #ids and used[ids[k]] do k = k + 1 end
                if k > #ids then return end
                idField(i).String = ids[k]
                used[ids[k]] = true
            end
        end
    end

    local function autoAssign()
        fillSlots(NL, function(i) return L(i, "Id") end, lightIds())
        fillSlots(NG, function(i) return G(i, "Id") end, groupIds())
    end

    -- ------------------------------------------------------------ scenes
    local function loadScenes()
        if bridgeIP() == "" or appKey() == "" then return end
        request("GET", apiUrl("/scenes"), nil, function(code, data)
            local t = code == 200 and decode(data) or nil
            if not t or hueError(t) then return end
            local byGroup = {}
            for sid, s in pairs(t) do
                if type(s) == "table" and s.type == "GroupScene" and s.group then
                    local gid = tostring(s.group)
                    byGroup[gid] = byGroup[gid] or {}
                    table.insert(byGroup[gid], { id = sid, name = s.name or sid })
                end
            end
            scenes = {}
            for gid, list in pairs(byGroup) do
                table.sort(list, function(a, b)
                    if a.name ~= b.name then return a.name < b.name end
                    return a.id < b.id
                end)
                local entry = { names = {}, ids = {} }
                local seen = {}
                for _, s in ipairs(list) do
                    local name = s.name
                    seen[name] = (seen[name] or 0) + 1
                    if seen[name] > 1 then name = name .. " (" .. seen[name] .. ")" end
                    table.insert(entry.names, name)
                    entry.ids[name] = s.id
                end
                scenes[gid] = entry
            end
            for i = 1, NG do applySceneChoices(i) end
        end)
    end

    -- ------------------------------------------------------------ polling
    local function pollFailed(code, err)
        setOnline(false)
        local why = (err and err ~= "") and tostring(err) or ("HTTP " .. tostring(code))
        setStatus("Bridge not responding (" .. why .. ")")
    end

    local function authFailed(e)
        setOnline(false)
        if e.type == 1 then
            setStatus("App key rejected by the bridge: press its link button, then Pair")
        else
            setStatus("Bridge error: " .. tostring(e.description))
        end
    end

    local function pollOk()
        setOnline(true)
        autoAssign()
        applyAll()
        updateLists()
        local nlights, ngroups = #lightIds(), #groupIds()
        setStatus(string.format("Online: %d light%s, %d room%s/zone%s on the bridge",
            nlights, nlights == 1 and "" or "s", ngroups, ngroups == 1 and "" or "s", ngroups == 1 and "" or "s"))
        if not wasOnline or pollCount % SCENE_EVERY == 0 then loadScenes() end
        wasOnline = true
        pollCount = pollCount + 1
    end

    function poll()
        if bridgeIP() == "" then
            setOnline(false)
            setStatus("Enter the bridge's IP address")
            return
        end
        if appKey() == "" then
            setOnline(false)
            setStatus("Not paired: press the bridge's link button, then Pair")
            return
        end
        if pollBusy and now() - pollStarted < POLL_GATE_S then return end
        pollBusy, pollStarted = true, now()
        local gen = pollGen
        request("GET", apiUrl("/lights"), nil, function(code, data, err)
            if gen ~= pollGen then return end   -- answer to an IP or key that has since changed
            local t = code == 200 and decode(data) or nil
            if not t then pollBusy = false; pollFailed(code, err); return end
            local e = hueError(t)
            if e then pollBusy = false; authFailed(e); return end
            local lights = t
            request("GET", apiUrl("/groups"), nil, function(code2, data2, err2)
                if gen ~= pollGen then return end
                pollBusy = false
                local g = code2 == 200 and decode(data2) or nil
                if not g then pollFailed(code2, err2); return end
                local e2 = hueError(g)
                if e2 then authFailed(e2); return end
                bridgeLights, bridgeGroups = lights, g
                pollOk()
            end)
        end)
    end

    -- ------------------------------------------------------------ commands
    -- Queue a change; changes to the same light or group merge, so a fader drag sends its latest value.
    local function connected()
        if bridgeIP() == "" or appKey() == "" then
            setStatus("Not connected: set the bridge IP and pair first", true)
            return false
        end
        return true
    end

    local function queue(key, path, body, isGroup)
        if not connected() then return false end
        local entry = pendingBody[key]
        if not entry then
            entry = { path = path, body = {}, group = isGroup }
            pendingBody[key] = entry
            table.insert(pendingOrder, key)
        end
        for k, v in pairs(body) do entry.body[k] = v end
        return true
    end

    local function queueLight(i, body)
        if not connected() then return end
        local id = idOf(L(i, "Id"))
        if id == "" then setStatus("Light slot " .. i .. " has no ID", true); return end
        holdL[i] = now() + HOLD_S
        queue("L" .. id, "/lights/" .. id .. "/state", body, false)
    end

    local function queueGroup(i, body)
        if not connected() then return end
        local id = idOf(G(i, "Id"))
        if id == "" then setStatus("Group slot " .. i .. " has no ID", true); return end
        holdG[i] = now() + HOLD_S
        queue("G" .. id, "/groups/" .. id .. "/action", body, true)
    end

    local function commandDone(code, data, err)
        if code ~= 200 then
            local why = (err and err ~= "") and tostring(err) or ("HTTP " .. tostring(code))
            setStatus("Command not sent (" .. why .. ")", true)
            return
        end
        local e = hueError(decode(data))
        if e then setStatus("Bridge: " .. tostring(e.description), true) end
    end

    -- One request per tick; group commands at least GROUP_GAP_S apart.
    function sendNext()
        local t = now()
        for idx, key in ipairs(pendingOrder) do
            local entry = pendingBody[key]
            if not entry.group or t - lastGroupSend >= GROUP_GAP_S then
                table.remove(pendingOrder, idx)
                pendingBody[key] = nil
                if entry.group then lastGroupSend = t end
                entry.body.transitiontime = TRANSITION
                request("PUT", apiUrl(entry.path), entry.body, commandDone)
                return
            end
        end
    end

    -- Brightness: 0 % turns off; above 0 turns on at that level.
    local function briBody(pct)
        if pct <= 0 then return { on = false }, false end
        return { on = true, bri = clamp(round(pct / 100 * 254), 1, 254) }, true
    end

    -- ------------------------------------------------------------ switches and motion sensors
    local function S(i, field) return Controls[SKey(i, field)] end
    local function M(i, field) return Controls[MKey(i, field)] end

    local function isSwitch(v) return v.type == "ZLLSwitch" or v.type == "ZGPSwitch" end
    local function isMotion(v) return v.type == "ZLLPresence" end

    local function sensorIds(filter)
        local ids = {}
        for id, v in pairs(bridgeSensors) do if type(v) == "table" and filter(v) then table.insert(ids, id) end end
        return numericSort(ids)
    end

    -- Hue Tap (ZGPSwitch) reports one code per button; everything else (ZLLSwitch) reports
    -- button * 1000 + 0 press, 1 hold, 2 short release, 3 long release.
    TAP_BUTTONS = { [34] = 1, [16] = 2, [17] = 3, [18] = 4 }
    ZLL_KINDS = { [0] = "press", [1] = "hold", [2] = "short release", [3] = "long release" }

    local function decodeButton(sensor, ev)
        if type(ev) ~= "number" then return nil end
        if sensor.type == "ZGPSwitch" then
            local b = TAP_BUTTONS[ev]
            if b then return b, "short release" end
            return nil
        end
        local b, code = math.tointeger(ev // 1000), math.tointeger(ev % 1000)
        if b and b >= 1 and b <= SWITCH_BUTTONS and ZLL_KINDS[code] then return b, ZLL_KINDS[code] end
        return nil
    end

    local function clearHolds(i)
        for b = 1, SWITCH_BUTTONS do S(i, "H" .. b).Boolean = false end
        holdSeen[i] = {}
    end

    -- A switch slot's name, battery and reachability, and the events since the last poll:
    -- short release pulses that button's Press pin; hold lights its Hold LED until a long release.
    local function applySwitch(i)
        local id = idOf(S(i, "Id"))
        local d = id ~= "" and bridgeSensors[id] or nil
        if type(d) ~= "table" then
            S(i, "Name").String = id == "" and "" or ("(no switch " .. id .. " on the bridge)")
            S(i, "Reach").Boolean = false
            S(i, "Event").String = ""
            switchSeen[i] = nil
            clearHolds(i)
            return
        end
        local cfg = type(d.config) == "table" and d.config or {}
        local st = type(d.state) == "table" and d.state or {}
        S(i, "Name").String = d.name or ""
        S(i, "Reach").Boolean = cfg.reachable ~= false   -- a Tap has no reachable flag
        if type(cfg.battery) == "number" then S(i, "Batt").Value = cfg.battery end

        local key = tostring(st.lastupdated) .. "|" .. tostring(st.buttonevent)
        local seen = switchSeen[i]
        switchSeen[i] = { id = id, key = key }
        local b, kind = decodeButton(d, st.buttonevent)
        local label = ""
        if b then label = string.format("Button %d %s", b, kind)
        elseif st.buttonevent then label = "Event " .. tostring(st.buttonevent) end
        if seen == nil or seen.id ~= id then
            S(i, "Event").String = label   -- first sighting: show it, fire nothing
            return
        end
        if seen.key == key then return end
        S(i, "Event").String = label
        if not b then return end
        if kind == "short release" then
            S(i, "H" .. b).Boolean = false
            holdSeen[i][b] = nil
            S(i, "P" .. b):Trigger()
        elseif kind == "hold" then
            S(i, "H" .. b).Boolean = true
            holdSeen[i][b] = now()
        elseif kind == "long release" then
            S(i, "H" .. b).Boolean = false
            holdSeen[i][b] = nil
        end
    end

    local function expireHolds()
        local t = now()
        for i = 1, NS do
            for b, at in pairs(holdSeen[i]) do
                if t - at > HOLD_EXPIRE_S then
                    S(i, "H" .. b).Boolean = false
                    holdSeen[i][b] = nil
                end
            end
        end
    end

    -- A Hue motion sensor is three bridge sensors (presence, light level, temperature) whose
    -- uniqueid shares the MAC-and-endpoint prefix; the slot holds the presence sensor's ID.
    local function prefixOf(v)
        if type(v.uniqueid) ~= "string" then return nil end
        return v.uniqueid:match("^(.*)%-%x+$")
    end

    local function companion(presence, sensorType)
        local pre = prefixOf(presence)
        if not pre then return nil end
        for _, v in pairs(bridgeSensors) do
            if type(v) == "table" and v.type == sensorType and prefixOf(v) == pre then return v end
        end
        return nil
    end

    local function applyMotion(i)
        local id = idOf(M(i, "Id"))
        local d = id ~= "" and bridgeSensors[id] or nil
        if type(d) ~= "table" then
            M(i, "Name").String = id == "" and "" or ("(no motion sensor " .. id .. " on the bridge)")
            M(i, "Presence").Boolean = false
            M(i, "Reach").Boolean = false
            return
        end
        local cfg = type(d.config) == "table" and d.config or {}
        local st = type(d.state) == "table" and d.state or {}
        M(i, "Name").String = d.name or ""
        M(i, "Presence").Boolean = st.presence == true
        M(i, "Reach").Boolean = cfg.reachable == true
        if type(cfg.battery) == "number" then M(i, "Batt").Value = cfg.battery end
        local ll = companion(d, "ZLLLightLevel")
        if ll and type(ll.state) == "table" and type(ll.state.lightlevel) == "number" then
            M(i, "Lux").Value = round(10 ^ ((ll.state.lightlevel - 1) / 10000))
        end
        local tt = companion(d, "ZLLTemperature")
        if tt and type(tt.state) == "table" and type(tt.state.temperature) == "number" then
            M(i, "Temp").Value = math.floor(tt.state.temperature / 10 + 0.5) / 10
        end
    end

    local function updateSensorList()
        local lines = {}
        for _, id in ipairs(sensorIds(function(v) return isSwitch(v) or isMotion(v) end)) do
            local v = bridgeSensors[id]
            local kind = isMotion(v) and "Motion" or "Switch"
            table.insert(lines, id .. "  " .. (v.name or "") .. "  (" .. kind .. ")")
        end
        Controls.BridgeSensors.Choices = lines
    end

    function pollSensors()
        if NS + NM == 0 or bridgeIP() == "" or appKey() == "" then return end
        if sensorBusy and now() - sensorStarted < POLL_GATE_S then return end
        sensorBusy, sensorStarted = true, now()
        local gen = pollGen
        request("GET", apiUrl("/sensors"), nil, function(code, data)
            if gen ~= pollGen then return end
            sensorBusy = false
            local t = code == 200 and decode(data) or nil
            if not t or hueError(t) then return end   -- the light poll reports the bridge's state
            bridgeSensors = t
            fillSlots(NS, function(i) return S(i, "Id") end, sensorIds(isSwitch))
            fillSlots(NM, function(i) return M(i, "Id") end, sensorIds(isMotion))
            for i = 1, NS do applySwitch(i) end
            for i = 1, NM do applyMotion(i) end
            expireHolds()
            updateSensorList()
        end)
    end

    -- ------------------------------------------------------------ pairing
    local function pairAttempt()
        if not pairing then return end
        if now() > pairDeadline then
            pairing = false
            pairTimer:Stop()
            setStatus("Pairing timed out: press the bridge's link button, then Pair again", true)
            return
        end
        request("POST", baseUrl() .. "/api", { devicetype = "qsys_hue#core" }, function(code, data, err)
            if not pairing then return end
            local t = code == 200 and decode(data) or nil
            local ok = t and type(t[1]) == "table" and type(t[1].success) == "table" and t[1].success.username
            if ok then
                pairing = false
                pairTimer:Stop()
                Controls.AppKey.String = tostring(ok)
                setStatus("Paired with the bridge", true)
                poll()
                return
            end
            local e = hueError(t)
            if e and e.type ~= 101 then
                pairing = false
                pairTimer:Stop()
                setStatus("Pairing failed: " .. tostring(e.description), true)
            elseif not t then
                Controls.Status.String = "Pairing: bridge not responding (" .. ((err and err ~= "") and tostring(err) or ("HTTP " .. tostring(code))) .. ")"
            end
        end)
    end

    local function startPairing()
        if bridgeIP() == "" then setStatus("Enter the bridge's IP address before pairing", true); return end
        pairing = true
        pairDeadline = now() + PAIR_WINDOW_S
        Controls.Status.String = "Pairing: press the link button on the bridge (30 s)"
        pairTimer:Start(2)
        pairAttempt()
    end

    -- ------------------------------------------------------------ handlers
    for i = 1, NL do
        L(i, "On").EventHandler = function(c) showOn(c, c.Boolean); queueLight(i, { on = c.Boolean }) end
        L(i, "Bri").EventHandler = function(c)
            local body, on = briBody(c.Value)
            showOn(L(i, "On"), on)
            queueLight(i, body)
        end
        L(i, "Ct").EventHandler = function(c) queueLight(i, { ct = clamp(round(1e6 / c.Value), 153, 500) }) end
        L(i, "Hue").EventHandler = function(c) queueLight(i, { hue = clamp(round(c.Value / 360 * 65535), 0, 65535) }) end
        L(i, "Sat").EventHandler = function(c) queueLight(i, { sat = clamp(round(c.Value / 100 * 254), 0, 254) }) end
        L(i, "Id").EventHandler = function() holdL[i] = nil; applyLight(i) end
    end

    for i = 1, NG do
        G(i, "On").EventHandler = function(c) showOn(c, c.Boolean); queueGroup(i, { on = c.Boolean }) end
        G(i, "Bri").EventHandler = function(c)
            local body, on = briBody(c.Value)
            showOn(G(i, "On"), on)
            queueGroup(i, body)
        end
        G(i, "Scene").EventHandler = function(c)
            local name = c.String
            local sc = scenes[idOf(G(i, "Id"))]
            local sid = sc and sc.ids[name]
            if not sid then
                setStatus("No scene named '" .. name .. "' in group slot " .. i, true)
                return
            end
            queueGroup(i, { scene = sid })
        end
        G(i, "Id").EventHandler = function() holdG[i] = nil; applyGroup(i) end
    end

    for i = 1, NS do
        S(i, "Id").EventHandler = function() switchSeen[i] = nil; clearHolds(i); applySwitch(i) end
    end
    for i = 1, NM do
        M(i, "Id").EventHandler = function() applyMotion(i) end
    end

    -- All On / All Off: group 0 is every light on the bridge. Every page's pair does the same.
    local function allLights(on) queue("G0", "/groups/0/action", { on = on }, true) end
    for _, pair in pairs(PAGE_ALL_BUTTONS) do
        if Controls[pair[1]] then Controls[pair[1]].EventHandler = function() allLights(true) end end
        if Controls[pair[2]] then Controls[pair[2]].EventHandler = function() allLights(false) end end
    end
    Controls.Refresh.EventHandler = function() poll(); loadScenes() end
    Controls.Pair.EventHandler = function() startPairing() end
    -- A new IP or key starts polling afresh, without waiting out a poll still pending for the old one.
    local function settingsChanged()
        pollGen = pollGen + 1
        pollBusy, sensorBusy = false, false
        setOnline(false)
        statusUntil = 0
        poll()
    end
    Controls.BridgeIP.EventHandler = function() settingsChanged() end
    Controls.AppKey.EventHandler = function() settingsChanged() end

    -- ------------------------------------------------------------ start
    if bridgeIP() == "" then Controls.BridgeIP.String = trim(Properties["Bridge IP"].Value) end
    if appKey() == "" then Controls.AppKey.String = trim(Properties["App Key"].Value) end
    Controls.Online.Boolean = false
    for i = 1, NL do showOn(L(i, "On"), L(i, "On").Boolean) end
    for i = 1, NG do showOn(G(i, "On"), G(i, "On").Boolean) end

    pollTimer = Timer.New()
    pollTimer.EventHandler = function() poll() end
    sendTimer = Timer.New()
    sendTimer.EventHandler = function() sendNext() end
    pairTimer = Timer.New()
    pairTimer.EventHandler = function() pairAttempt() end

    sensorTimer = Timer.New()
    sensorTimer.EventHandler = function() pollSensors() end

    pollTimer:Start(POLL_S)
    sendTimer:Start(SEND_TICK_S)
    sensorTimer:Start(SENSOR_POLL_S)
    poll()
    pollSensors()
end
