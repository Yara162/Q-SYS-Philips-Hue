<img src="assets/smartspaces-logo.png" alt="SmartSpaces" width="240">

# Q-SYS Philips Hue

A Q-SYS plugin that controls Philips Hue lights, rooms and zones, and reads Hue switches and motion sensors, through a Hue Bridge on the local network. It pairs with the bridge from its own panel, polls the bridge for feedback, and exposes every control as a pin.

- **Lights:** on/off, brightness, colour temperature, hue, saturation, reachable, name.
- **Rooms and zones:** on/off, brightness, scene recall from the bridge's own scenes.
- **Scene buttons:** per room or zone, an On and an Off button and up to 8 buttons, each set to a scene, ready to place on a UCI.
- **Switches:** a Press and a Hold output per button, battery, last event.
- **Motion sensors:** presence, light level, temperature, battery.
- **All On / All Off** for every light on the bridge, at the top of every page.

Made by YZ at the SmartSpaces programming department. Provided as-is, under the [MIT License](LICENSE).

## Tested On

| | |
|---|---|
| Q-SYS Core | Core Nano, firmware 10.5.1-2610.002 |
| Hue Bridge | Hue Bridge v2 (BSB002), firmware 1978688000, API 1.78 |
| Switches | Hue Dimmer switch v2 (RWL022) |

Confirmed on that hardware: pairing, light and room control and feedback, scenes and scene buttons, All On / All Off, switch presses (Press outputs driving wired logic), and Use HTTPS.

Not yet tried on hardware: motion sensors, switch holds, the Hue Tap and other switch types, and the bridge going offline mid-session.

## Install

The plugin ships as two identical files; use either one.

- **`philips-hue.qplug`:** double-click it, and Q-SYS Designer installs it.
- **`philips-hue.lua`:** in Q-SYS Designer, **Tools > Design Resources > Import**, and pick `philips-hue.lua`.

Then:

1. Drag **Philips Hue** from the User tree (folder *Smart Spaces WI*) into the design.
2. In Properties, set how many slots you want: **Light Count** (1–32), **Group Count** (rooms and zones, 0–16), **Scene Buttons per Room** (0–8), **Switch Count** (0–16), **Motion Count** (0–8).

## Pair with the bridge

1. Run the design (emulation, or a Core with network access to the bridge).
2. On the **Setup** page, type the bridge's IP address into **Bridge IP**.
3. Press **Pair**, then press the round link button on the bridge within 30 seconds.
4. **App Key** fills in, **Online** lights, and the slots fill with the bridge's lights, rooms, switches and motion sensors.

An existing Hue application key can be pasted into **App Key** instead.

**Properties vs the Setup page.** The **Bridge IP** and **App Key** properties are stored in the design file. At start, each fills its Setup field only when that field is empty, so a value already in the field wins. For a delivered system, put the IP and key in the properties: after pairing, copy the key from the field into the property.

## Slots

Every light, room/zone, switch and motion sensor slot has an **ID** field: the bridge's number for that device. The Setup page lists everything on the bridge with its ID.

- Every empty slot is filled, top down, with the bridge's devices of that kind that aren't already in a slot, in ID order. Rooms and zones leave out entertainment areas. Raising a count fills the new rows the same way, and a device added to the bridge lands in the next empty slot.
- `-` in an ID field keeps that slot blank: it's never filled.
- Typing an ID shows that device at once. An ID the bridge doesn't have shows *(no light N on the bridge)* (or switch, motion sensor) as the name.

## Controls

Pins are named by slot, e.g. *Light 03 Brightness*, *Group 02 Scene Button 1*, *Switch 01 Button 2 Press*, *Motion 01 Presence*, *All Off*. ON buttons read ON or OFF with the state, and every fader has its value beside it (%, K, °).

| Page | Control | Pin | Notes |
|---|---|---|---|
| Lights | ON | both | Toggle. |
| | BRIGHTNESS | both | 0–100 %. **0 % turns the light off**; any value above 0 turns it on at that level. |
| | COLOR TEMP | both | 2000–6500 K. A light without colour temperature reports the bridge's error on Status. |
| | HUE, SAT | both | 0–360°, 0–100 %. Colour lights only. |
| | REACH | output | The bridge can reach the light. |
| | NAME | output | The light's name on the bridge. |
| Rooms & Zones | ON | both | On when any light in the room is on, as the Hue app shows it. |
| | BRIGHTNESS | both | 0 % turns the room off. |
| | SCENE | both | The bridge's scenes for that room or zone. Picking one, or writing a scene name to the pin, recalls it. Two scenes with the same name show as *Name* and *Name (2)*. |
| | NAME | output | |
| Scene Buttons | On, Off | input | Turn that room or zone on or off. |
| | Scene picker (per button) | both | Sets the button's scene from the room's scenes. Writing a scene name to the pin sets it too. Kept in the design. |
| | Scene Button 1–8 | input | Recalls the scene set above it. Captioned with the scene's name. |
| Switches & Sensors | Button 1–4 Press | output (LED) | Lights for half a second each time that button is pressed and released on the switch. |
| | Button 1–4 Hold | output (LED) | On while that button is held down on the switch. |
| | LAST EVENT | output | e.g. *Button 2 short release*. |
| | BATT, REACH, NAME | output | Battery %, the bridge can reach it, its name. |
| | PRESENCE | output | Motion sensor: someone is there. |
| | LIGHT LUX, TEMP C | output | Motion sensor: light level in lux, temperature in °C. |
| | Sensor Poll Status | output | When sensors were last read, poll and failure counts, time of the last switch event. |
| Setup | Online | output | The last poll reached the bridge with a valid key. |
| | Status | output | What the plugin is doing, or the last error. |
| | Refresh | input | Poll and reload scenes now. |
| | All On, All Off | input | Turn every light on the bridge on or off. Every page but About has its own pair at the top (panel only); the Setup pair carries the pins. |
| About | | | Credits, licence, version. |

## Switches and motion sensors

The plugin reads the bridge's sensors twice a second. It takes switches the bridge reports as `ZLLSwitch` (Hue Dimmer, Smart Button, wall switch module, the Tap Dial's buttons) or `ZGPSwitch` (Hue Tap).

- **Switches report; the plugin can't press them.** Press and Hold are outputs for driving Q-SYS logic from a physical switch. Hue offers no way for an app to fire a switch's button or the action it's set to in the Hue app. To do from Q-SYS what a dimmer does, use the room's On, Off, Brightness and scene buttons.
- **Latency:** a press reaches its pin 0–0.5 s after it happens. That suits a button that recalls a scene or starts a macro; it's too slow to feel right for hold-to-dim.
- **Repeats:** the bridge stamps events to the second, so two presses of the same button within one second count as one.
- **The bridge keeps its own rules.** A switch still does whatever the Hue app set it to do. For a switch that drives only Q-SYS, remove its actions in the Hue app.
- **Restarts don't replay:** Last Event shows the bridge's last event at start, but nothing fires.
- **Hold** needs a real hold: the switch reports it after about a second held down. A quick press is a Press, never a Hold.
- Every new switch event is written to the plugin's Debug Output, e.g. *Switch 01 (Living room switch): Button 2 short release*. A sensor poll failure and its recovery are written once each.
- A Hue motion sensor appears on the bridge as three sensors (presence, light level, temperature). Its slot takes the presence sensor's ID; the other two are found by their shared unique ID.

## Properties

| Property | Default | |
|---|---|---|
| Bridge IP | *empty* | Fills the Bridge IP field when it's empty at start. |
| App Key | *empty* | Fills the App Key field when it's empty at start. |
| Use HTTPS | off | Talk to the bridge over `https://`. Works on the tested Core and bridge. |
| Light Count | 8 | Light slots, 1–32. |
| Group Count | 4 | Room/zone slots, 0–16. 0 removes the Rooms & Zones and Scene Buttons pages. |
| Scene Buttons per Room | 4 | Scene buttons per room/zone, 0–8, four to a row. The On and Off buttons are always there. |
| Switch Count | 4 | Switch slots, 0–16. |
| Motion Count | 2 | Motion sensor slots, 0–8. With Switch Count also 0, the Switches & Sensors page is removed and sensors aren't polled. |
| Poll Interval (seconds) | 3 | Seconds between light and room polls, 1–60. |
| Transition Time (x100 ms) | 4 | Fade time for commands, in 100 ms steps (4 = 400 ms, Hue's default). Off commands never fade: see below. |
| Log Sensor Data | off | Writes the raw `lastupdated` and `buttonevent` the plugin receives for each switch to the Debug Output when they change, plus a summary every 10 s. For troubleshooting switches. |

## How it talks to the bridge

- **API:** Hue CLIP v1 (`/api/<key>/...`) over HTTP. The Hue Bridge v2 serves it, and plain HTTP avoids depending on certificate handling in the Core's HTTP client.
- **Feedback:** `/lights` and `/groups` every Poll Interval, `/sensors` every 0.5 s (only with switch or motion slots), `/scenes` about once a minute.
- **Pacing:** commands are queued and sent one per 125 ms, with room/zone commands at least 1 s apart, so commands and polls stay inside Hue's published limits. Changes to the same light merge in the queue, so a fader drag sends only its latest value.
- **Off never fades.** An off command with a fade time makes Hue fade the light to its minimum and store that, so it would come back on at 1 %. Off commands go out without one, so All On, a light's ON or a room's ON bring each light back at the brightness it had.
- **Hold-off:** after a change, polls leave that light's or room's controls alone for 3 s, so a fader doesn't jump back mid-drag.
- **Failures:** if the bridge stops answering, Online goes off, Status says why, and every control keeps its last value until the bridge answers again.

## Tests

`tests/` holds two checks that run without a Core:

```bash
python tests/structural.py philips-hue.qplug
```

```bash
lua5.3 tests/sim.lua philips-hue.qplug
```

- `structural.py` checks the file as text: balanced blocks, every control and property the runtime uses is declared, no local function called before it's defined, and the `.lua` and `.qplug` are identical.
- `sim.lua` runs the real plugin under Lua 5.3 against stand-ins for the Q-SYS runtime and a fake Hue Bridge, and checks every page's layout and the behaviour above. Its header lists what the stand-ins assume about Q-SYS and the bridge, and which of those held on the hardware above.
- `soak.lua` runs the plugin for hours of simulated time (continuous polling, switch presses, fader moves, scene recalls, a bridge outage every hour) and checks that its memory stays flat: `lua5.3 tests/soak.lua philips-hue.qplug 8`. Over 8 simulated hours it holds at about 600 KB.

The plugin writes no files. Its only output is lines in the Debug Output: one per switch event, one per sensor poll failure and recovery, and, with Log Sensor Data on, raw switch values when they change plus a summary every 10 s.

`assets/` holds the SmartSpaces logo; the About page carries it embedded in the plugin.

## License

MIT, copyright (c) 2026 YZ, SmartSpaces. Free to use, change and share, as long as the copyright notice and licence text stay with it. See [LICENSE](LICENSE).

Philips Hue is a trademark of Signify. This plugin is not made, endorsed or supported by Signify.
