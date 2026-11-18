-- Runs the Philips Hue plugin for hours of simulated time against the same stand-ins as sim.lua
-- and checks that its memory stays flat: no table, timer or closure that grows with every poll.
-- Usage (from the plugin folder):
--   lua5.3 tests/soak.lua philips-hue.qplug [hours]
-- Each simulated hour has continuous polling (lights every 3 s, sensors every 0.5 s), a switch
-- press every 30 s, a fader move every minute, a scene recall every 5 minutes, and a 2-minute
-- bridge outage. After each hour it forces a full garbage collection and prints Lua's memory in
-- use. Exits 1 if memory after the last hour is more than 10 % (plus 64 KB) above the first hour.

local PLUGIN = arg[1] or "philips-hue.qplug"
SOAK_HOURS = tonumber(arg[2]) or 8   -- global: the loaded chunk reads it

-- Reuse sim.lua's stand-ins: everything above its first test section.
local f = assert(io.open("tests/sim.lua", "r"))
local src = f:read("a")
f:close()
local cut = src:find("%-%- %-+ layout\n")
assert(cut, "tests/sim.lua: stand-ins section not found")

local soak = [==[
-- One-shot timers end when they fire, as on a Core; the harness drops them from its list.
local function pruneTimers()
    local keep = {}
    for _, t in ipairs(TIMERS) do if not (t.oneShot and t.nextAt == nil) then table.insert(keep, t) end end
    TIMERS = keep
end
local function patchCallAfter()
    Timer.CallAfter = function(fn, delay)
        local t = newTimer()
        t.oneShot = true
        t.EventHandler = function() t:Stop(); fn() end
        t:Start(delay)
    end
end

freshBridge()
boot({ ["Bridge IP"] = "192.168.1.50", ["App Key"] = "validkey", ["Log Sensor Data"] = true })
patchCallAfter()
advance(5)
user("G01Sc1", "String", "Relax")

local samples = {}
local press = 0
for hour = 1, SOAK_HOURS do
    for minute = 1, 60 do
        for half = 1, 2 do
            press = press + 1
            switchEvent("2", (press % 4 + 1) * 1000 + 2)
            BRIDGE.sensors["2"].state.lastupdated = BRIDGE.sensors["2"].state.lastupdated .. "-" .. press
            advance(30)
        end
        user("L01Bri", "Value", (minute * 7) % 100)
        if minute % 5 == 0 then Controls["G01Go1"].EventHandler(Controls["G01Go1"]) end
        if minute == 30 then BRIDGE.online = false end
        if minute == 32 then BRIDGE.online = true end
    end
    -- Harness bookkeeping is not the plugin's memory: clear it before measuring.
    HTTP_LOG, BRIDGE.puts, PRINTED = {}, {}, {}
    pruneTimers()
    collectgarbage("collect"); collectgarbage("collect")
    samples[hour] = collectgarbage("count")
    io.write(string.format("hour %d: %.0f KB in use, %d timers, %d pending commands, status: %s\n",
        hour, samples[hour], #TIMERS, #pendingOrder, Controls.SensorStatus.String))
end

local first, last = samples[1], samples[#samples]
local ok = last <= first * 1.10 + 64
io.write(string.format("\n%s  memory after hour 1: %.0f KB, after hour %d: %.0f KB\n", ok and "PASS" or "FAIL", first, #samples, last))
os.exit(ok and 0 or 1)
]==]

local harness = src:sub(1, cut - 1):gsub('local PLUGIN = arg%[1%] or "philips%-hue.qplug"', 'local PLUGIN = "' .. PLUGIN .. '"')
local chunk = assert(load(harness .. soak, "=soak"))
chunk()
