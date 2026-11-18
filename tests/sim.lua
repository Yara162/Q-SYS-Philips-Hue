-- Runs the Philips Hue plugin's real code under Lua 5.3 against stand-ins for the Q-SYS runtime and
-- a fake Hue Bridge, and checks every page's layout and the plugin's behaviour. Usage (from the
-- plugin folder):
--   lua5.3 tests/sim.lua philips-hue.qplug
-- Prints PASS/FAIL per check; exits 0 when all pass.

-- ASSUMPTIONS: what the stand-ins believe about Q-SYS and the Hue Bridge. A green run shows the
-- plugin's logic is right if these hold, nothing more. "Confirmed" means it held on the hardware
-- listed in the README's Tested On section; "not confirmed" lines are the places where the sim can
-- pass and a Core can still behave differently. If a Core contradicts a line, fix the stand-in so
-- the sim reproduces the Core, then fix the plugin.
--
--  1. GetControlLayout is called once per page with props["page_index"].Value (1-based), and the
--     props carry the plugin's own properties. Confirmed.
--  2. Writing .Value / .Boolean / .String / .Choices from Lua does not fire that control's
--     EventHandler; only a user or a wired pin does. Confirmed (polling sends no commands).
--  3. Setting .Boolean sets .Value to 1/0 and the reverse; a Knob clamps .Value to its Min/Max.
--     Standard Q-SYS behaviour.
--  4. rapidjson.encode writes a Lua integer as a JSON integer (100, not 100.0). The fake bridge
--     rejects a float where Hue wants an integer. Confirmed.
--  5. HttpClient.Get / HttpClient.Upload{Method=...} call EventHandler(tbl, code, data, err) once per
--     request, including on a timeout or an unreachable host (code ~= 200). Confirmed for success;
--     the timeout case is not confirmed.
--  6. A Text control shown as a ComboBox or ListBox takes a runtime .Choices list, and picking an
--     item sets .String and fires the EventHandler. Confirmed.
--  7. Timer.Now() is a seconds clock; Timer.New():Start(s) fires every s seconds until Stop;
--     Timer.CallAfter(f, s) calls f once. The sim drives all three from one fake clock.
--  8. The Hue Bridge v1 API behaves as the fake bridge does: GET /lights, /groups, /scenes keyed by
--     id strings; PUT /lights/<id>/state and /groups/<id>/action answer an array of success/error
--     items; error 1 = unauthorized user, 101 = link button not pressed, 6 = parameter not
--     available, 7 = invalid value; POST /api {devicetype} gives {success={username}} after the
--     link button; groups/0 is every light; scenes of type GroupScene carry their group id.
--     Confirmed.
--  9. The stand-ins don't model a runtime .Color. On a Core, a Text control's .Color paints its field
--     as well as its text, so the sim checks the runtime never sets one. Observed on QDS 10.5.1.
-- 10. Toggle-button layout keys Color / OffColor / UnlinkOffColor render lit vs unlit, and a
--     runtime .Legend write changes the caption. Confirmed.
-- 11. A layout entry's PrettyName is the name the Control Pins list shows. Confirmed.
-- 12. A Knob shown with layout Style "Text" (read-only) displays its value as text. Confirmed.
-- 13. An LED declared as an output pin drives its pin from .Boolean, so a 0.5 s Press pulse reaches
--     wired logic. Confirmed.
-- 14. Hue /sensors: a ZLLSwitch reports buttonevent = button * 1000 + 0 press / 1 hold / 2 short
--     release / 3 long release, with a new state.lastupdated (1 s resolution) per event. Confirmed
--     for press and short release on Hue Dimmer v2 (RWL022); holds not confirmed. A ZGPSwitch
--     (Tap) reports 34/16/17/18 for buttons 1-4: not confirmed.
-- 15. A Hue motion sensor is a ZLLPresence, a ZLLLightLevel and a ZLLTemperature sharing a uniqueid
--     prefix; lux = 10^((lightlevel - 1) / 10000); temperature is in 0.01 C. Not confirmed.
-- 16. A layout graphic of Type "Image" shows the base64 PNG in its Image key. Not confirmed.
-- 17. Hue: on=false with a transitiontime fades the light and stores brightness 1, so it comes back
--     on at 1 %. The fake bridge does the same. Confirmed.
-- 18. print() writes a line to the plugin's Debug Output.

local PLUGIN = arg[1] or "philips-hue.qplug"
local chunk = assert(loadfile(PLUGIN))
local passed, failed = 0, 0
local function check(name, ok, detail)
    if ok then passed = passed + 1 else failed = failed + 1 end
    io.write((ok and "PASS  " or "FAIL  ") .. name .. ((not ok and detail ~= nil) and ("  -- " .. tostring(detail)) or ""), "\n")
end

-- ---------------------------------------------------------------- JSON (the rapidjson stand-in)
local function encode(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if math.type(v) == "integer" then return string.format("%d", v) end
        local s = string.format("%.17g", v)
        if not s:find("[%.eEn]") then s = s .. ".0" end
        return s
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    end
    local n = 0
    for _ in pairs(v) do n = n + 1 end
    if n > 0 and #v == n then
        local parts = {}
        for _, x in ipairs(v) do table.insert(parts, encode(x)) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do table.insert(parts, encode(k) .. ":" .. encode(v[k] == nil and v[tonumber(k)] or v[k])) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function decode(s)
    local pos = 1
    local function ws() pos = s:find("[^%s]", pos) or #s + 1 end
    local value
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                if e == "u" then table.insert(out, utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))); pos = pos + 6
                else table.insert(out, ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e); pos = pos + 2 end
            else
                table.insert(out, c); pos = pos + 1
            end
            if pos > #s then error("unterminated string") end
        end
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                ws(); local k = str(); ws()
                assert(s:sub(pos, pos) == ":", "expected :"); pos = pos + 1
                t[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "}" then return t end
                assert(d == ",", "expected ,")
            end
        elseif c == "[" then
            local t = {}
            pos = pos + 1; ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                table.insert(t, value()); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == "]" then return t end
                assert(d == ",", "expected ,")
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            assert(num and num ~= "", "bad json at " .. pos)
            pos = pos + #num
            return math.tointeger(tonumber(num)) and not num:find("[%.eE]") and math.tointeger(tonumber(num)) or tonumber(num) + 0.0
        end
    end
    local v = value()
    return v
end

package.preload["rapidjson"] = function()
    return { encode = encode, decode = function(s) local ok, v = pcall(decode, s) if ok then return v end return nil, v end }
end

-- ---------------------------------------------------------------- clock and timers
local CLOCK = 1000.0
local TIMERS = {}
PRINTED = {}
print = function(...) local parts = {} for _, v in ipairs({ ... }) do table.insert(parts, tostring(v)) end table.insert(PRINTED, table.concat(parts, "\t")) end
local real_print = io.write
local function out(line) io.write(line, "\n") end

local function newTimer()
    local t = { interval = nil, nextAt = nil }
    function t:Start(s) self.interval = s; self.nextAt = CLOCK + s end
    function t:Stop() self.interval = nil; self.nextAt = nil end
    function t:IsRunning() return self.interval ~= nil end
    table.insert(TIMERS, t)
    return t
end

-- ---------------------------------------------------------------- fake Hue Bridge
local BRIDGE
local function freshBridge()
    BRIDGE = {
        ip = "192.168.1.50",
        online = true,
        key = "validkey",
        link = false,
        lights = {
            ["1"]  = { name = "Desk",    type = "Extended color light", state = { on = false, bri = 127, ct = 366, hue = 0, sat = 0, reachable = true } },
            ["2"]  = { name = "Ceiling", type = "Color temperature light", state = { on = true, bri = 254, ct = 250, reachable = true } },
            ["3"]  = { name = "Hall",    type = "Dimmable light", state = { on = false, bri = 50, reachable = false } },
            ["10"] = { name = "Porch",   type = "Extended color light", state = { on = false, bri = 200, ct = 300, hue = 1000, sat = 100, reachable = true } },
        },
        groups = {
            ["1"] = { name = "Office", type = "Room", lights = { "1", "2" }, state = { any_on = true, all_on = false }, action = { on = true, bri = 254 } },
            ["2"] = { name = "Outside", type = "Zone", lights = { "10" }, state = { any_on = false, all_on = false }, action = { on = false, bri = 200 } },
            ["3"] = { name = "TV area", type = "Entertainment", lights = { "1" }, state = { any_on = false, all_on = false }, action = { on = false, bri = 127 } },
        },
        scenes = {
            abc = { name = "Relax",  type = "GroupScene", group = "1" },
            def = { name = "Bright", type = "GroupScene", group = "1" },
            xyz = { name = "Relax",  type = "GroupScene", group = "1" },
            nnn = { name = "Night",  type = "GroupScene", group = "2" },
            lll = { name = "Old",    type = "LightScene", lights = { "1" } },
        },
        sensors = {
            ["1"]  = { name = "Daylight", type = "Daylight", config = { on = true }, state = { daylight = true } },
            ["2"]  = { name = "Office dimmer", type = "ZLLSwitch", uniqueid = "00:17:88:01:aa:bb:cc:dd-02-fc00",
                       config = { on = true, battery = 90, reachable = true }, state = { buttonevent = 1002, lastupdated = "2026-11-18T01:00:00" } },
            ["5"]  = { name = "Hall tap", type = "ZGPSwitch", uniqueid = "00:00:00:00:00:44:23:08-f2",
                       config = { on = true }, state = { buttonevent = 34, lastupdated = "2026-11-18T01:00:00" } },
            ["7"]  = { name = "Hall motion", type = "ZLLPresence", uniqueid = "00:17:88:01:02:00:af:28-02-0406",
                       config = { on = true, battery = 80, reachable = true }, state = { presence = false, lastupdated = "2026-11-18T01:00:00" } },
            ["8"]  = { name = "Hall light level", type = "ZLLLightLevel", uniqueid = "00:17:88:01:02:00:af:28-02-0400",
                       config = { on = true, battery = 80, reachable = true }, state = { lightlevel = 20001, dark = false } },
            ["9"]  = { name = "Hall temperature", type = "ZLLTemperature", uniqueid = "00:17:88:01:02:00:af:28-02-0402",
                       config = { on = true, battery = 80, reachable = true }, state = { temperature = 2150 } },
            ["12"] = { name = "Tap dial rotary", type = "ZLLRelativeRotary", uniqueid = "00:17:88:01:0b:00:11:22-01-fc00",
                       config = { on = true, reachable = true }, state = { rotaryevent = 1 } },
        },
        puts = {},      -- every PUT the bridge received: { path, body, at }
        recalled = nil,
        drop = false,   -- swallow requests without ever answering
    }
end

local INT_PARAMS = { bri = true, ct = true, hue = true, sat = true, transitiontime = true }

local function bridgeRespond(method, url, data)
    if not BRIDGE.online then return 0, "", "Timeout was reached" end
    local host, path = url:match("^https?://([^/]+)(/.*)$")
    if host ~= BRIDGE.ip then return 0, "", "Couldn't connect to server" end
    local err = function(t, addr, desc) return 200, encode({ { error = { type = t, address = addr, description = desc } } }) end
    if method == "POST" and path == "/api" then
        local body = decode(data)
        if type(body) ~= "table" or type(body.devicetype) ~= "string" then return err(5, "/", "invalid/missing parameters in body") end
        if not BRIDGE.link then return err(101, "", "link button not pressed") end
        BRIDGE.key = "newkey"
        return 200, encode({ { success = { username = "newkey" } } })
    end
    local key, rest = path:match("^/api/([^/]*)(.*)$")
    if key ~= BRIDGE.key then return err(1, rest ~= "" and rest or "/", "unauthorized user") end
    if method == "GET" then
        if rest == "/lights" then return 200, encode(BRIDGE.lights) end
        if rest == "/groups" then return 200, encode(BRIDGE.groups) end
        if rest == "/scenes" then return 200, encode(BRIDGE.scenes) end
        if rest == "/sensors" then return 200, encode(BRIDGE.sensors) end
        return err(3, rest, "resource not available")
    end
    if method == "PUT" then
        local body = decode(data)
        table.insert(BRIDGE.puts, { path = rest, body = body, at = CLOCK })
        for k, v in pairs(body) do
            if INT_PARAMS[k] and math.type(v) ~= "integer" then return err(7, rest .. "/" .. k, "invalid value, " .. tostring(v) .. ", for parameter, " .. k) end
        end
        local lid = rest:match("^/lights/([^/]+)/state$")
        if lid then
            local L = BRIDGE.lights[lid]
            if not L then return err(3, rest, "resource, /lights/" .. lid .. ", not available") end
            local out = {}
            -- Hue quirk: off with a transitiontime fades the light down and stores brightness 1.
            if body.on == false and body.transitiontime ~= nil and L.state.bri then L.state.bri = 1 end
            for k, v in pairs(body) do
                if k ~= "transitiontime" then
                    if L.state[k] == nil then return err(6, rest .. "/" .. k, "parameter, " .. k .. ", not available") end
                    L.state[k] = v
                    table.insert(out, { success = { [rest .. "/" .. k] = v } })
                end
            end
            return 200, encode(out)
        end
        local gid = rest:match("^/groups/([^/]+)/action$")
        if gid then
            local members = {}
            if gid == "0" then for id in pairs(BRIDGE.lights) do table.insert(members, id) end
            elseif BRIDGE.groups[gid] then members = BRIDGE.groups[gid].lights
            else return err(3, rest, "resource, /groups/" .. gid .. ", not available") end
            if body.scene then
                if not BRIDGE.scenes[body.scene] then return err(7, rest .. "/scene", "invalid value for parameter, scene") end
                BRIDGE.recalled = { group = gid, scene = body.scene }
            end
            for _, id in ipairs(members) do
                if body.on == false and body.transitiontime ~= nil then BRIDGE.lights[id].state.bri = 1 end   -- same quirk
                if body.on ~= nil then BRIDGE.lights[id].state.on = body.on end
                if body.bri ~= nil then BRIDGE.lights[id].state.bri = body.bri end
            end
            local g = BRIDGE.groups[gid]
            if g then
                if body.on ~= nil then g.action.on = body.on; g.state.any_on = body.on; g.state.all_on = body.on end
                if body.bri ~= nil then g.action.bri = body.bri end
            end
            return 200, encode({ { success = { [rest .. "/on"] = body.on } } })
        end
        return err(3, rest, "resource not available")
    end
    return err(4, rest, "method not available")
end

-- The HttpClient stand-in queues requests; flush() answers them through the fake bridge.
local HTTP_QUEUE, HTTP_LOG = {}, {}
local function httpCall(method, args)
    table.insert(HTTP_QUEUE, { method = method, args = args })
    table.insert(HTTP_LOG, { method = method, url = args.Url, data = args.Data, at = CLOCK })
end
local function flush()
    local n = 0
    while #HTTP_QUEUE > 0 do
        local r = table.remove(HTTP_QUEUE, 1)
        if not BRIDGE.drop then
            local code, data, err = bridgeRespond(r.method, r.args.Url, r.args.Data)
            r.args.EventHandler(r.args, code, data, err)
        end
        n = n + 1
        if n > 10000 then error("request loop") end
    end
end

-- Advance the clock in 50 ms steps, firing due timers and answering requests as they're made.
local AUTO_FLUSH = true
local function advance(seconds)
    local stop = CLOCK + seconds
    while CLOCK < stop - 1e-9 do
        CLOCK = math.min(stop, CLOCK + 0.05)
        for _, t in ipairs(TIMERS) do
            if t.nextAt and CLOCK >= t.nextAt - 1e-9 then
                t.nextAt = t.nextAt + t.interval
                t.EventHandler(t)
            end
        end
        if AUTO_FLUSH then flush() end
    end
end

-- ---------------------------------------------------------------- controls
local COLOR_WRITES = {}
local function control(decl)
    local raw = { String = "", Value = 0, Boolean = false, Choices = nil, Legend = nil, EventHandler = nil, rises = 0 }
    local c = {}
    setmetatable(c, {
        __index = raw,
        __newindex = function(_, k, v)
            if k == "Boolean" then
                if v and not raw.Boolean then raw.rises = raw.rises + 1 end   -- off -> on edges, for pulse counting
                raw.Boolean = v and true or false; raw.Value = v and 1 or 0
            elseif k == "Value" then
                if decl.Min then v = math.max(decl.Min, math.min(decl.Max, v)) end
                raw.Value = v; raw.Boolean = v > 0.5
                if decl.ControlType == "Knob" then raw.String = tostring(v) end
            elseif k == "Color" then
                table.insert(COLOR_WRITES, decl.Name); raw.Color = v
            else
                raw[k] = v
            end
        end,
    })
    return c
end

local function props(t)
    local p = {}
    for k, v in pairs(t) do p[k] = { Value = v } end
    return p
end

local DEFAULT_PROPS = { ["Bridge IP"] = "", ["App Key"] = "", ["Use HTTPS"] = false, ["Light Count"] = 8,
    ["Group Count"] = 4, ["Scene Buttons per Room"] = 4, ["Switch Count"] = 4, ["Motion Count"] = 2, ["Poll Interval (seconds)"] = 3, ["Transition Time (x100 ms)"] = 4, ["Log Sensor Data"] = false }

local function withProps(over)
    local t = {}
    for k, v in pairs(DEFAULT_PROPS) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

-- Design time: Controls = nil, as Designer runs the file.
Controls = nil
Properties = nil
chunk()

-- One start of the plugin on a Core: fresh controls (holding `panel`, name -> string), then the runtime.
local DECLARED
local function boot(propOver, panel)
    local p = withProps(propOver)
    DECLARED = {}
    for _, c in ipairs(GetControls(props(p))) do DECLARED[c.Name] = c end
    Controls = {}
    for name, decl in pairs(DECLARED) do Controls[name] = control(decl) end
    for name, s in pairs(panel or {}) do Controls[name].String = s end
    Properties = props(p)
    TIMERS, HTTP_QUEUE, HTTP_LOG, COLOR_WRITES = {}, {}, {}, {}
    Timer = { New = newTimer, Now = function() return CLOCK end,
        CallAfter = function(f, delay) local t = newTimer(); t.EventHandler = function() t:Stop(); f() end; t:Start(delay) end }
    HttpClient = {
        Get = function(a) httpCall("GET", a) end,
        Upload = function(a) httpCall(a.Method or "POST", a) end,
    }
    local ok, err = pcall(chunk)
    if AUTO_FLUSH then flush() end
    return ok, err
end

local function user(name, field, value)
    local c = Controls[name]
    c[field] = value
    c.EventHandler(c)
end
local function press(name) user(name, "Boolean", true) end
local function status() return Controls.Status.String end
local function ctl(name) return Controls[name] end
local function count(method, pattern)
    local n = 0
    for _, r in ipairs(HTTP_LOG) do if r.method == method and (not pattern or r.url:find(pattern)) then n = n + 1 end end
    return n
end
-- How many times a Press LED has lit (each press is one off -> on edge).
local function triggers(name) return Controls[name].rises end
-- A button event on the bridge, stamped with the bridge's 1 s resolution lastupdated.
local function switchEvent(id, ev)
    BRIDGE.sensors[id].state.buttonevent = ev
    BRIDGE.sensors[id].state.lastupdated = os.date("!%Y-%m-%dT%H:%M:%S", math.floor(CLOCK))
end

local function putsTo(path)
    local out = {}
    for _, p in ipairs(BRIDGE.puts) do if p.path == path then table.insert(out, p) end end
    return out
end

-- ---------------------------------------------------------------- layout
local function checkLayout(label, p)
    local pr = props(withProps(p))
    local declared = {}
    for _, c in ipairs(GetControls(pr)) do declared[c.Name] = c end
    local pages = GetPages(pr)
    local placed = {}
    for page = 1, #pages do
        pr["page_index"] = { Value = page }
        local layout, graphics = GetControlLayout(pr)
        local tag = ("%s page %d (%s)"):format(label, page, pages[page].name)
        local bg = graphics[1]
        local w, h = bg.Size[1], bg.Size[2]
        local unknown, outside, uncaptioned = {}, {}, {}
        for name, l in pairs(layout) do
            placed[name] = true
            if not declared[name] then table.insert(unknown, name) end
            if l.Style ~= "None" and (l.Position[1] < 0 or l.Position[2] < 0 or l.Position[1] + l.Size[1] > w or l.Position[2] + l.Size[2] > h) then
                table.insert(outside, name)
            end
            if l.Style == "Button" and (type(l.Legend) ~= "string" or l.Legend == "" or not l.ButtonStyle or l.Text or l.ButtonType) then
                table.insert(uncaptioned, name)
            end
        end
        for i = 2, #graphics do
            local g = graphics[i]
            if g.Position[1] + g.Size[1] > w or g.Position[2] + g.Size[2] > h then table.insert(outside, "graphic " .. i) end
        end
        check(tag .. ": every layout key is a declared control", #unknown == 0, table.concat(unknown, ", "))
        check(("%s: everything sits inside the %dx%d panel"):format(tag, w, h), #outside == 0, table.concat(outside, ", "))
        check(tag .. ": background is sized, not a 1 px strip", h > 100, h)
        check(tag .. ": every button has a Legend and a ButtonStyle", #uncaptioned == 0, table.concat(uncaptioned, ", "))
        local raw, seen, dup = {}, {}, {}
        for name, l in pairs(layout) do
            if type(l.PrettyName) ~= "string" or l.PrettyName == "" or l.PrettyName:find("^[LG]%d%d") then table.insert(raw, name) end
            if l.PrettyName then
                if seen[l.PrettyName] then table.insert(dup, l.PrettyName) end
                seen[l.PrettyName] = true
            end
        end
        check(tag .. ": every control has a human PrettyName", #raw == 0, table.concat(raw, ", "))
        check(tag .. ": no two controls share a PrettyName", #dup == 0, table.concat(dup, ", "))
    end
    local unplaced = {}
    for name in pairs(declared) do if not placed[name] then table.insert(unplaced, name) end end
    check(label .. ": every control has a layout on some page (none auto-placed)", #unplaced == 0, table.concat(unplaced, ", "))
    return pages
end

checkLayout("default", {})
checkLayout("max slots", { ["Light Count"] = 32, ["Group Count"] = 16 })
local p0 = checkLayout("no groups", { ["Group Count"] = 0 })
check("Group Count 0 drops the Groups and Scene Buttons pages", #p0 == 4 and p0[1].name == "Lights" and p0[2].name == "Switches & Sensors")
local pfull = checkLayout("max sensors", { ["Switch Count"] = 16, ["Motion Count"] = 8 })
check("pages: Lights, Groups, Scene Buttons, Switches & Sensors, Setup, About", #pfull == 6 and pfull[3].name == "Scene Buttons" and pfull[4].name == "Switches & Sensors" and pfull[6].name == "About",
    #pfull)
local pns = checkLayout("no sensors", { ["Switch Count"] = 0, ["Motion Count"] = 0 })
check("Switch and Motion Count 0 drop the Switches & Sensors page", #pns == 5 and pns[4].name == "Setup")
checkLayout("motion only", { ["Switch Count"] = 0, ["Motion Count"] = 3 })
do
    local pr = props(withProps({}))
    pr["page_index"] = { Value = #GetPages(pr) }   -- About is last
    local _, graphics = GetControlLayout(pr)
    local image, text = nil, {}
    for _, g in ipairs(graphics) do
        if g.Type == "Image" then image = g end
        if g.Type == "Label" then table.insert(text, g.Text) end
    end
    local all = table.concat(text, " ")
    check("About page shows the logo as a base64 PNG", image and type(image.Image) == "string" and image.Image:sub(1, 11) == "iVBORw0KGgo")
    check("About page credits YZ at SmartSpaces, as-is, MIT", all:find("Made by YZ at the SmartSpaces programming department") and all:find("as%-is") and all:find("MIT License"), all)
end

-- ---------------------------------------------------------------- start-up states
freshBridge()
local ok, err = boot({})
check("plugin starts with no properties set", ok, err)
check("no bridge IP: asks for it, Online off, sends nothing", status():find("IP address") ~= nil and not ctl("Online").Boolean and #HTTP_LOG == 0, status())

ok, err = boot({ ["Bridge IP"] = "192.168.1.50" })
check("IP but no key: says not paired, sends nothing", ok and status():find("Not paired") ~= nil and #HTTP_LOG == 0, status())

-- ---------------------------------------------------------------- pairing
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50" })
press("Pair")
check("Pair before the link button: keeps trying and says so", status():find("press the link button") ~= nil and count("POST", "/api$") == 1, status())
advance(6)
check("pairing retries every 2 s", count("POST", "/api$") == 4, count("POST", "/api$"))
check("poll messages don't overwrite the pairing prompt", status():find("Pairing") ~= nil, status())
BRIDGE.link = true
advance(2.5)
check("link pressed: App Key fills from the bridge", ctl("AppKey").String == "newkey", ctl("AppKey").String)
check("then it goes Online", ctl("Online").Boolean, status())
local postsAfter = count("POST", "/api$")
advance(6)
check("pairing stops once paired", count("POST", "/api$") == postsAfter, count("POST", "/api$"))

check("blank plugin auto-fills light slots in numeric ID order", ctl("L01Id").String == "1" and ctl("L02Id").String == "2" and ctl("L03Id").String == "3" and ctl("L04Id").String == "10" and ctl("L05Id").String == "",
    ctl("L01Id").String .. "," .. ctl("L02Id").String .. "," .. ctl("L03Id").String .. "," .. ctl("L04Id").String)
check("group slots get Rooms and Zones only (no Entertainment area)", ctl("G01Id").String == "1" and ctl("G02Id").String == "2" and ctl("G03Id").String == "", ctl("G03Id").String)
check("Setup lists every bridge light", ctl("BridgeLights").Choices and #ctl("BridgeLights").Choices == 4 and ctl("BridgeLights").Choices[4]:find("Porch") ~= nil)
check("Setup lists rooms and zones with their type", ctl("BridgeGroups").Choices and #ctl("BridgeGroups").Choices == 2 and ctl("BridgeGroups").Choices[2]:find("Zone") ~= nil)

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50" })
press("Pair")
advance(33)          -- the 30 s window closes at the first 2 s retry after it
check("no link press in 30 s: pairing times out and says so", status():find("timed out") ~= nil and ctl("AppKey").String == "", status())
local n = count("POST", "/api$")
advance(6)
check("and stops trying", count("POST", "/api$") == n)

-- ---------------------------------------------------------------- feedback
freshBridge()
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
check("properties seed the Bridge IP and App Key fields", ok and ctl("BridgeIP").String == "192.168.1.50" and ctl("AppKey").String == "validkey", err)
check("first poll at start: Online, status counts lights and rooms/zones", ctl("Online").Boolean and status():find("4 lights, 2 rooms/zones") ~= nil, status())
check("names come from the bridge", ctl("L01Name").String == "Desk" and ctl("G01Name").String == "Office")
check("brightness 127/254 shows 50 %", ctl("L01Bri").Value == 50, ctl("L01Bri").Value)
check("colour temperature 366 mired shows 2732 K", ctl("L01Ct").Value == 2732, ctl("L01Ct").Value)
check("on/off and reachable follow the bridge", ctl("L02On").Boolean and not ctl("L01On").Boolean and ctl("L01Reach").Boolean and not ctl("L03Reach").Boolean)
check("hue and saturation follow the bridge", ctl("L04Hue").Value == 5 and ctl("L04Sat").Value == 39, ctl("L04Hue").Value .. "/" .. ctl("L04Sat").Value)
check("group ON follows any_on, brightness follows the group action", ctl("G01On").Boolean and not ctl("G02On").Boolean and ctl("G01Bri").Value == 100)
check("toggle captions follow the bridge: ON when on, OFF when off", ctl("L02On").Legend == "ON" and ctl("L01On").Legend == "OFF" and ctl("G01On").Legend == "ON" and ctl("G02On").Legend == "OFF",
    tostring(ctl("L02On").Legend) .. "/" .. tostring(ctl("L01On").Legend) .. "/" .. tostring(ctl("G01On").Legend) .. "/" .. tostring(ctl("G02On").Legend))
check("an empty slot's toggle says OFF", ctl("L05On").Legend == "OFF", ctl("L05On").Legend)
check("scene list for a room: sorted, duplicate names numbered", table.concat(ctl("G01Scene").Choices or {}, "|") == "Bright|Relax|Relax (2)", table.concat(ctl("G01Scene").Choices or {}, "|"))
check("each room only lists its own scenes", table.concat(ctl("G02Scene").Choices or {}, "|") == "Night")
check("polling alone sends no commands", count("PUT") == 0, count("PUT"))
check("the runtime never sets a control's .Color", #COLOR_WRITES == 0, table.concat(COLOR_WRITES, ", "))

-- ---------------------------------------------------------------- commands
advance(1)
user("L01On", "Boolean", true)
advance(0.2)
local p = putsTo("/lights/1/state")
check("ON sends on=true to that light", #p == 1 and p[1].body.on == true and BRIDGE.lights["1"].state.on == true, #p)
check("pressing ON changes its caption to ON at once", ctl("L01On").Legend == "ON", ctl("L01On").Legend)
check("every command carries transitiontime from the property", #p == 1 and p[1].body.transitiontime == 4)

advance(1)
for v = 10, 90, 10 do user("L01Bri", "Value", v) end
advance(0.3)
p = putsTo("/lights/1/state")
check("a fader drag between ticks sends one command with the latest value", #p == 2 and p[2].body.bri == 229 and p[2].body.on == true, #p .. " puts, bri " .. tostring(p[#p].body.bri))
check("brightness reaches the bridge as an integer (no rejection)", BRIDGE.lights["1"].state.bri == 229 and status():find("invalid value") == nil, status())

advance(1)
user("L01Bri", "Value", 0)
advance(0.2)
p = putsTo("/lights/1/state")
check("brightness 0 % turns the light off", p[#p].body.on == false and p[#p].body.bri == nil and not ctl("L01On").Boolean and BRIDGE.lights["1"].state.on == false)
check("and its toggle caption says OFF", ctl("L01On").Legend == "OFF", ctl("L01On").Legend)

advance(1)
user("L01Ct", "Value", 4000); advance(0.2)
user("L01Hue", "Value", 180); advance(0.2)
user("L01Sat", "Value", 50); advance(0.2)
local s1 = BRIDGE.lights["1"].state
check("colour temp 4000 K sends 250 mired", s1.ct == 250, s1.ct)
check("hue 180 deg sends 32768, sat 50 % sends 127", s1.hue == 32768 and s1.sat == 127, tostring(s1.hue) .. "/" .. tostring(s1.sat))

advance(1)
user("L03Ct", "Value", 3000); advance(0.2)
check("a light without colour temperature: the bridge's error shows on Status", status():find("parameter, ct, not available") ~= nil, status())
advance(3.5)
check("the error holds against routine poll messages for a while", status():find("not available") ~= nil, status())
advance(8)
check("then routine status returns", status():find("Online") ~= nil, status())

-- ---------------------------------------------------------------- hold-off
advance(1)
AUTO_FLUSH = false
flush()
advance(2.9)         -- a poll is now waiting for its answer, carrying the bridge's old brightness
user("L02Bri", "Value", 30)
local old = BRIDGE.lights["2"].state.bri
flush()              -- the stale poll answer arrives before the command is sent
check("a poll answer older than the change doesn't move the fader back", ctl("L02Bri").Value == 30 and old == 254, ctl("L02Bri").Value)
AUTO_FLUSH = true
advance(0.2)
check("then the change reaches the bridge", BRIDGE.lights["2"].state.bri == 76, BRIDGE.lights["2"].state.bri)
advance(4)
BRIDGE.lights["2"].state.bri = 254   -- someone uses the Hue app
advance(3.1)
check("after the hold-off, changes made elsewhere show up", ctl("L02Bri").Value == 100, ctl("L02Bri").Value)
check("and showing them sends nothing back", putsTo("/lights/2/state")[2] == nil)

-- ---------------------------------------------------------------- groups and pacing
advance(2)
local before = #BRIDGE.puts
user("G01On", "Boolean", false)
user("G02Bri", "Value", 60)
press("AllOff")
user("L04On", "Boolean", true)
advance(0.15)
local first = BRIDGE.puts[before + 1]
advance(3)
local groupTimes, lightAt = {}, nil
for idx = before + 1, #BRIDGE.puts do
    local q = BRIDGE.puts[idx]
    if q.path:find("^/groups/") then table.insert(groupTimes, q.at) elseif q.path == "/lights/10/state" then lightAt = q.at end
end
local spaced = #groupTimes == 3
for k = 2, #groupTimes do if groupTimes[k] - groupTimes[k - 1] < 1 - 1e-6 then spaced = false end end
check("group commands go out at least 1 s apart", spaced, #groupTimes .. " group puts")
check("a light command isn't stuck behind the group queue", lightAt and lightAt < groupTimes[3], lightAt)
check("group ON sends to /groups/<id>/action", first and first.path == "/groups/1/action" and first.body.on == false)
check("All Off sends on=false to group 0 (every light)", #putsTo("/groups/0/action") == 1 and BRIDGE.lights["2"].state.on == false)

advance(2)
user("G01Scene", "String", "Relax")
advance(1.2)
check("picking a scene recalls it in that room", BRIDGE.recalled and BRIDGE.recalled.group == "1" and BRIDGE.recalled.scene == "abc", BRIDGE.recalled and BRIDGE.recalled.scene)
user("G01Scene", "String", "Relax (2)")
advance(1.2)
check("a numbered duplicate recalls the other scene", BRIDGE.recalled.scene == "xyz", BRIDGE.recalled.scene)
user("G02Scene", "String", "Night")
advance(1.2)
check("a scene picked in the second slot goes to that slot's zone", BRIDGE.recalled.group == "2" and BRIDGE.recalled.scene == "nnn", BRIDGE.recalled.group .. "/" .. BRIDGE.recalled.scene)
local putsNow = #BRIDGE.puts
user("G01Scene", "String", "Disco")
advance(1.2)
check("an unknown scene name says so and sends nothing", status():find("No scene named 'Disco'") ~= nil and #BRIDGE.puts == putsNow, status())

-- ---------------------------------------------------------------- slot IDs
advance(12)
user("L02Id", "String", "-")
advance(3.1)
check("a slot set to '-' stays blank and isn't refilled", ctl("L02Id").String == "-" and ctl("L02Name").String == "")
user("L02Id", "String", "")
advance(3.1)
check("the light that '-' freed goes to the first empty slot", ctl("L05Id").String == "2", ctl("L05Id").String)
check("a cleared slot stays empty while every bridge light already has a slot", ctl("L02Id").String == "", ctl("L02Id").String)
user("L05Id", "String", "-")
advance(3.1)
check("once a light is free again, the top empty slot takes it", ctl("L02Id").String == "2" and ctl("L02Name").String == "Ceiling", ctl("L02Id").String)
user("L02Id", "String", "99")
check("an ID the bridge doesn't have says so", ctl("L02Name").String:find("no light 99") ~= nil, ctl("L02Name").String)
user("L02Id", "String", "10")
check("typing an ID shows that light at once", ctl("L02Name").String == "Porch")

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" }, { L01Id = "3", L02Id = "-", L03Id = "1" })
check("empty slots fill with the lights not already in a slot, in ID order",
    ctl("L01Id").String == "3" and ctl("L02Id").String == "-" and ctl("L03Id").String == "1" and ctl("L04Id").String == "2" and ctl("L05Id").String == "10" and ctl("L06Id").String == "",
    table.concat({ ctl("L01Id").String, ctl("L02Id").String, ctl("L03Id").String, ctl("L04Id").String, ctl("L05Id").String, ctl("L06Id").String }, ","))

-- Light Count raised after the first fill: the new rows fill, the old ones keep their IDs.
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Light Count"] = 2, ["Group Count"] = 1 })
local small = { L01Id = ctl("L01Id").String, L02Id = ctl("L02Id").String, G01Id = ctl("G01Id").String }
check("with 2 light slots and 1 group slot, the first lights and room fill", small.L01Id == "1" and small.L02Id == "2" and small.G01Id == "1")
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Light Count"] = 8, ["Group Count"] = 4 }, small)
check("raising Light Count fills the new rows with the remaining lights", ctl("L01Id").String == "1" and ctl("L03Id").String == "3" and ctl("L04Id").String == "10" and ctl("L05Id").String == "",
    ctl("L03Id").String .. "," .. ctl("L04Id").String)
check("raising Group Count brings in the zone", ctl("G01Id").String == "1" and ctl("G02Id").String == "2" and ctl("G03Id").String == "", ctl("G02Id").String)

-- ---------------------------------------------------------------- failures
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(1)
BRIDGE.online = false
advance(3.1)
check("bridge unreachable: Online off, status says why", not ctl("Online").Boolean and status():find("not responding") ~= nil, status())
check("and every control keeps its last value", ctl("L01Name").String == "Desk" and ctl("L02On").Boolean and ctl("L01Bri").Value == 50)
BRIDGE.online = true
advance(3.1)
check("bridge back: Online again", ctl("Online").Boolean, status())

BRIDGE.drop = true
local gets = count("GET", "/lights$")
advance(9.1)
check("a poll that never answers isn't stacked by the next ones", count("GET", "/lights$") == gets + 1, count("GET", "/lights$") - gets)
advance(12)
check("after the gate, polling tries again", count("GET", "/lights$") > gets + 1)
BRIDGE.drop = false
user("AppKey", "String", "wrongkey")   -- while a dropped poll still holds the gate
advance(0.1)
check("a rejected app key says pair again", not ctl("Online").Boolean and status():find("App key rejected") ~= nil, status())

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50" })
user("L01On", "Boolean", true)
check("a command while unpaired says so and sends nothing", status():find("Not connected") ~= nil and count("PUT") == 0, status())

freshBridge()
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Group Count"] = 0 })
check("Group Count 0 runs, lights still work", ok and ctl("Online").Boolean and ctl("L01Name").String == "Desk", err or status())


-- ---------------------------------------------------------------- switches and motion sensors
freshBridge()
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
check("starts with switch and motion slots", ok, err)
check("switch slots fill with switches only, in ID order (no rotary, no daylight)", ctl("S01Id").String == "2" and ctl("S02Id").String == "5" and ctl("S03Id").String == "",
    ctl("S01Id").String .. "," .. ctl("S02Id").String .. "," .. ctl("S03Id").String)
check("motion slots fill with the presence sensor's ID", ctl("M01Id").String == "7" and ctl("M02Id").String == "", ctl("M01Id").String)
check("Setup lists the bridge's switches and motion sensors", ctl("BridgeSensors").Choices and #ctl("BridgeSensors").Choices == 3 and ctl("BridgeSensors").Choices[3]:find("Motion") ~= nil,
    ctl("BridgeSensors").Choices and table.concat(ctl("BridgeSensors").Choices, " | "))
check("switch name, battery and reachable come from the bridge", ctl("S01Name").String == "Office dimmer" and ctl("S01Batt").Value == 90 and ctl("S01Reach").Boolean)
check("a Tap (no reachable flag) shows reachable", ctl("S02Reach").Boolean)
check("the first sighting shows the last event but fires nothing", ctl("S01Event").String == "Button 1 short release" and triggers("S01P1") == 0, ctl("S01Event").String)

advance(1)
local g0 = count("GET", "/sensors$")
advance(2)
check("switches and sensors are polled every 0.5 s", count("GET", "/sensors$") - g0 == 4, count("GET", "/sensors$") - g0)

switchEvent("2", 2002); advance(0.6)
check("a short press pulses that button's Press pin", triggers("S01P2") == 1 and triggers("S01P1") == 0, triggers("S01P2"))
check("and shows on Last Event", ctl("S01Event").String == "Button 2 short release", ctl("S01Event").String)
advance(0.6)
check("the same event isn't fired again on the next poll", triggers("S01P2") == 1, triggers("S01P2"))
advance(1); switchEvent("2", 2002); advance(0.6)
check("the same button pressed again later fires again", triggers("S01P2") == 2, triggers("S01P2"))

advance(1); switchEvent("2", 3000); advance(0.6)
switchEvent("2", 3001); advance(0.6)
check("a hold lights that button's Hold LED", ctl("S01H3").Boolean and not ctl("S01H2").Boolean)
advance(0.5); switchEvent("2", 3001); advance(0.6)
check("repeated hold events keep it lit", ctl("S01H3").Boolean)
advance(0.5); switchEvent("2", 3003); advance(0.6)
check("a long release clears it and fires no press", not ctl("S01H3").Boolean and triggers("S01P3") == 0)

advance(1); switchEvent("2", 4001); advance(0.6)
check("hold on button 4", ctl("S01H4").Boolean)
advance(3.6)
check("a Hold LED whose long release was missed clears itself after 3 s", not ctl("S01H4").Boolean)

advance(1); switchEvent("5", 16); advance(0.6)
check("a Tap press pulses its button (16 = button 2)", triggers("S02P2") == 1 and ctl("S02Event").String == "Button 2 short release", ctl("S02Event").String)

check("motion: name, presence, battery, reachable", ctl("M01Name").String == "Hall motion" and not ctl("M01Presence").Boolean and ctl("M01Batt").Value == 80 and ctl("M01Reach").Boolean)
check("light level 20001 shows 100 lux (from the sensor sharing its uniqueid)", ctl("M01Lux").Value == 100, ctl("M01Lux").Value)
check("temperature 2150 shows 21.5 C", ctl("M01Temp").Value == 21.5, ctl("M01Temp").Value)
BRIDGE.sensors["7"].state.presence = true; advance(0.6)
check("presence lights the Presence LED", ctl("M01Presence").Boolean)
BRIDGE.sensors["7"].state.presence = false; advance(0.6)
check("and clears with it", not ctl("M01Presence").Boolean)

local before = triggers("S01P2")
local panel = {}
for name, c in pairs(Controls) do panel[name] = c.String end
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" }, panel)
advance(1)
check("a restart doesn't replay the last event (no press, no hold)", triggers("S01P2") == 0 and not ctl("S01H4").Boolean and ctl("S01Event").String == "Button 4 hold", ctl("S01Event").String)

user("S01Id", "String", "5"); advance(0.6)
check("pointing a slot at another switch fires nothing for its old event", triggers("S01P2") == 0 and ctl("S01Name").String == "Hall tap")
user("S03Id", "String", "-"); advance(0.6)
check("'-' keeps a switch slot blank", ctl("S03Id").String == "-" and ctl("S03Name").String == "")
user("M01Id", "String", "8"); advance(0.6)
check("a motion slot pointed at a non-presence sensor keeps reading what's there", ctl("M01Name").String == "Hall light level")

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Switch Count"] = 0, ["Motion Count"] = 0 })
advance(3)
check("with no switch or motion slots, /sensors is never polled", count("GET", "/sensors$") == 0, count("GET", "/sensors$"))

-- ---------------------------------------------------------------- brightness survives All Off / All On
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(1)
press("AllOff"); advance(1.2)
press("AllOn"); advance(1.2)
check("All Off then All On brings lights back at their brightness, not 1 %", BRIDGE.lights["2"].state.bri == 254 and BRIDGE.lights["10"].state.bri == 200,
    BRIDGE.lights["2"].state.bri .. "/" .. BRIDGE.lights["10"].state.bri)
user("L02On", "Boolean", false); advance(0.3)
user("L02On", "Boolean", true); advance(0.3)
check("a light's own OFF then ON keeps its brightness", BRIDGE.lights["2"].state.bri == 254, BRIDGE.lights["2"].state.bri)

-- ---------------------------------------------------------------- All On / All Off on every page
do
    local pr = props(withProps({}))
    local pages = GetPages(pr)
    local missing = {}
    for page = 1, #pages do
        pr["page_index"] = { Value = page }
        local layout = GetControlLayout(pr)
        local on, off = 0, 0
        for _, l in pairs(layout) do
            if l.Style == "Button" and l.Legend == "All On" and l.Position[2] < 30 then on = on + 1 end
            if l.Style == "Button" and l.Legend == "All Off" and l.Position[2] < 30 then off = off + 1 end
        end
        local want = pages[page].name == "About" and 0 or 1
        if on ~= want or off ~= want then table.insert(missing, pages[page].name .. " " .. on .. "/" .. off) end
    end
    check("every page but About has All On and All Off at the top", #missing == 0, table.concat(missing, ", "))
end

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(1)
local pairsToTry = { { "AllOnLights", true }, { "AllOffGroups", false }, { "AllOnSensors", true }, { "AllOff", false }, { "AllOn", true }, { "AllOffLights", false } }
local allOk, why = true, {}
for _, t in ipairs(pairsToTry) do
    press(t[1]); advance(1.2)
    local q = putsTo("/groups/0/action")
    local last = q[#q]
    if not last or last.body.on ~= t[2] or BRIDGE.lights["10"].state.on ~= t[2] then allOk = false; table.insert(why, t[1]) end
end
check("each page's All On / All Off sends on=true / on=false to every light (group 0)", allOk, table.concat(why, ", "))
press("AllOnScenes"); advance(1.2)
check("the Scene Buttons page has its own working All On", putsTo("/groups/0/action")[#putsTo("/groups/0/action")].body.on == true)
check("All Off goes out without a transitiontime (Hue would store brightness 1)", putsTo("/groups/0/action")[2].body.transitiontime == nil and putsTo("/groups/0/action")[1].body.transitiontime == 4)

freshBridge()
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Group Count"] = 0, ["Switch Count"] = 0, ["Motion Count"] = 0 })
check("with no Groups or Sensors pages, their All On/Off buttons aren't declared", ok and Controls.AllOnGroups == nil and Controls.AllOnSensors == nil and Controls.AllOnLights ~= nil, err)


-- ---------------------------------------------------------------- fader readouts and scene buttons
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
check("number readouts beside the faders follow the bridge", ctl("L01BriV").String == "50%" and ctl("L01CtV").String == "2732K" and ctl("L04HueV").String == "5\u{B0}" and ctl("L04SatV").String == "39%" and ctl("G01BriV").String == "100%",
    table.concat({ ctl("L01BriV").String, ctl("L01CtV").String, ctl("L04HueV").String, ctl("L04SatV").String, ctl("G01BriV").String }, " "))
advance(1)
user("L01Bri", "Value", 73); user("L01Ct", "Value", 4100)
check("moving a fader updates its readout at once", ctl("L01BriV").String == "73%" and ctl("L01CtV").String == "4100K", ctl("L01BriV").String .. " " .. ctl("L01CtV").String)
user("G02Bri", "Value", 12)
check("a room fader updates its readout too", ctl("G02BriV").String == "12%", ctl("G02BriV").String)
check("an empty light slot's readouts show a number, not blank", ctl("L06BriV").String == "0%", ctl("L06BriV").String)

check("scene pickers list the room's scenes", table.concat(ctl("G01Sc1").Choices or {}, "|") == "Bright|Relax|Relax (2)" and table.concat(ctl("G02Sc4").Choices or {}, "|") == "Night")
check("an unset scene button is captioned 'Scene N'", ctl("G01Go2").Legend == "Scene 2", ctl("G01Go2").Legend)
check("the Scene Buttons page shows each room's name", ctl("G01NameB").String == "Office" and ctl("G02NameB").String == "Outside", ctl("G01NameB").String)
advance(1)
user("G01Sc2", "String", "Relax")
check("picking a scene captions the button with it", ctl("G01Go2").Legend == "Relax", ctl("G01Go2").Legend)
press("G01Go2"); advance(1.2)
check("pressing the scene button recalls that scene in that room", BRIDGE.recalled and BRIDGE.recalled.group == "1" and BRIDGE.recalled.scene == "abc", BRIDGE.recalled and BRIDGE.recalled.scene)
user("G02Sc4", "String", "Night"); press("G02Go4"); advance(1.2)
check("each room's buttons recall in their own room", BRIDGE.recalled.group == "2" and BRIDGE.recalled.scene == "nnn", BRIDGE.recalled.group)
local n0 = #BRIDGE.puts
press("G01Go3"); advance(1.2)
check("an unset scene button says so and sends nothing", status():find("scene button 3 has no scene set") ~= nil and #BRIDGE.puts == n0, status())
local panel13 = {}
for name, c in pairs(Controls) do panel13[name] = c.String end
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" }, panel13)
check("scene button settings and captions survive a restart", ctl("G01Sc2").String == "Relax" and ctl("G01Go2").Legend == "Relax", ctl("G01Go2").Legend)

-- ---------------------------------------------------------------- scene buttons per room; room On and Off
checkLayout("6 scene buttons", { ["Scene Buttons per Room"] = 6 })
checkLayout("8 scene buttons, 16 rooms", { ["Scene Buttons per Room"] = 8, ["Group Count"] = 16 })
checkLayout("no scene buttons", { ["Scene Buttons per Room"] = 0 })
freshBridge()
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Scene Buttons per Room"] = 6 })
check("Scene Buttons per Room 6 gives six buttons per room", ok and Controls.G01Go6 ~= nil and Controls.G04Sc6 ~= nil and Controls.G01Go7 == nil, err)
check("the extra buttons get the room's scenes and a caption", table.concat(ctl("G01Sc6").Choices or {}, "|") == "Bright|Relax|Relax (2)" and ctl("G01Go6").Legend == "Scene 6")
advance(1); user("G01Sc6", "String", "Bright"); press("G01Go6"); advance(1.2)
check("button 6 recalls its scene", BRIDGE.recalled and BRIDGE.recalled.scene == "def", BRIDGE.recalled and BRIDGE.recalled.scene)
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Scene Buttons per Room"] = 2 })
check("Scene Buttons per Room 2 gives two", ok and Controls.G01Go2 ~= nil and Controls.G01Go3 == nil, err)
ok, err = boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Scene Buttons per Room"] = 0 })
check("0 leaves only On and Off on the Scene Buttons page", ok and Controls.G01Go1 == nil and Controls.G01OnB ~= nil, err)

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(1)
press("G02OnB"); advance(1.2)
local gp = putsTo("/groups/2/action")
check("a room's On button turns that room on", #gp == 1 and gp[1].body.on == true and BRIDGE.lights["10"].state.on == true and ctl("G02On").Boolean, #gp)
press("G01OffB"); advance(1.2)
gp = putsTo("/groups/1/action")
check("a room's Off button turns that room off, without a fade", gp[#gp].body.on == false and gp[#gp].body.transitiontime == nil and BRIDGE.lights["1"].state.on == false and not ctl("G01On").Boolean)
check("On and Off buttons have human pin names", PrettyFor("G03OnB") == "Group 03 On Button" and PrettyFor("G03OffB") == "Group 03 Off Button" and PrettyFor("G03Go7") == "Group 03 Scene Button 7" and PrettyFor("G03Sc7") == "Group 03 Scene Button 7 Scene")

-- ---------------------------------------------------------------- sensor poll status line
freshBridge()
PRINTED = {}
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(2.1)
local polls = tonumber(ctl("SensorStatus").String:match("(%d+) polls"))
check("the status line counts sensor polls", polls and polls >= 4 and ctl("SensorStatus").String:find("0 failed") ~= nil, ctl("SensorStatus").String)
switchEvent("2", 1002); advance(0.6)
check("and shows when a switch last reported something new", ctl("SensorStatus").String:find("last switch event %d%d:%d%d:%d%d") ~= nil, ctl("SensorStatus").String)
BRIDGE.online = false; advance(1.6)
check("failed sensor polls are counted", tonumber(ctl("SensorStatus").String:match("(%d+) failed")) >= 2, ctl("SensorStatus").String)
local fails = 0
for _, l in ipairs(PRINTED) do if l:find("^Sensors: poll failed") then fails = fails + 1 end end
check("a run of failures is printed once, not every poll", fails == 1, fails)
BRIDGE.online = true; advance(0.6)
check("recovery is printed", table.concat(PRINTED, "\n"):find("Sensors: polling again") ~= nil)
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Switch Count"] = 0, ["Motion Count"] = 0 })
check("no status line control without switch or motion slots", Controls.SensorStatus == nil)

-- ---------------------------------------------------------------- Log Sensor Data
freshBridge()
PRINTED = {}
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Log Sensor Data"] = true })
advance(1)
local function linesMatching(pat) local n = 0 for _, l in ipairs(PRINTED) do if l:find(pat) then n = n + 1 end end return n end
check("with Log Sensor Data on, each switch's raw values are printed once at start", linesMatching("^Sensor data: poll %d+, switch 01 %(ID 2%): lastupdated=2026%-11%-18T01:00:00 buttonevent=1002 %(integer%)") == 1, table.concat(PRINTED, " / "))
switchEvent("2", 4002); advance(0.6)
check("and again when they change", linesMatching("switch 01 %(ID 2%): lastupdated=.- buttonevent=4002") == 1)
advance(10)
check("with a summary every 20 polls naming the reply size", linesMatching("^Sensor data: poll %d+, reply %d+ bytes, 01:") >= 1)
PRINTED = {}
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(11)
check("with it off, nothing is printed", linesMatching("^Sensor data") == 0)

-- ---------------------------------------------------------------- Press LEDs and the event log
freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey" })
advance(1)
PRINTED = {}
switchEvent("2", 2002); advance(0.6)
local logged = table.concat(PRINTED, "\n")
check("a new switch event is written to the debug output", logged:find("Switch 01 %(Office dimmer%): Button 2 short release %[buttonevent 2002") ~= nil, logged)
check("Press is an LED output, not a button", DECLARED["S01P1"].ControlType == "Indicator" and DECLARED["S01P1"].IndicatorType == "Led" and DECLARED["S01P1"].PinStyle == "Output")
do
    local pr = props(withProps({}))
    local pages = GetPages(pr)
    for page = 1, #pages do
        if pages[page].name == "Switches & Sensors" then
            pr["page_index"] = { Value = page }
            local layout = GetControlLayout(pr)
            check("Press shows as an LED on the panel", layout["S01P1"].Style == "Led" and layout["S03P4"].Style == "Led", layout["S01P1"].Style)
        end
    end
end
advance(1); switchEvent("2", 3002)
local wentOn, onFor = false, 0
for _ = 1, 30 do
    advance(0.05)
    if Controls.S01P3.Boolean then wentOn = true; onFor = onFor + 0.05 end
end
check("a press lights its Press LED", wentOn)
check("for about half a second", Controls.S01P3.Boolean == false and onFor > 0.35 and onFor < 0.7, onFor)
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
