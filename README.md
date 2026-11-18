<img src="assets/smartspaces-logo.png" alt="SmartSpaces" width="240">

# Q-SYS Philips Hue

A Q-SYS plugin that controls Philips Hue lights, rooms and zones, and reads Hue switches and motion sensors, through a Hue Bridge on the local network. It pairs with the bridge from the plugin's own panel, polls for feedback, and exposes every control as a pin.

- **Lights:** on/off, brightness, colour temperature, hue, saturation, reachable status, name.
- **Rooms and zones:** on/off, brightness, scene recall from the bridge's own scenes.
- **Switches:** a Press pin and a Hold pin per button, battery, last event.
- **Motion sensors:** presence, light level, temperature, battery.
- **All On / All Off** for every light on the bridge, at the top of every page.

Made by YZ at the SmartSpaces programming department. Provided as-is, under the [MIT License](LICENSE).

## Install

The plugin ships as two identical files; use either one.

- **`philips-hue.qplug`:** double-click it, and Q-SYS Designer installs it.
- **`philips-hue.lua`:** in Q-SYS Designer, **Tools > Design Resources > Import**, and pick `philips-hue.lua`.

Then:

1. Drag **Philips Hue** from the User tree (folder *Smart Spaces WI*) into the design.
2. In Properties, set how many slots you want: **Light Count** (1–32), **Group Count** (rooms and zones, 0–16), **Switch Count** (0–16), **Motion Count** (0–8).

## Pair with the bridge

1. Run the design (emulation or on a Core with network access to the bridge).
2. On the **Setup** page, type the bridge's IP address into **Bridge IP**.
3. Press **Pair**, then press the round link button on the bridge within 30 seconds.
4. **App Key** fills in, **Online** lights, and the slots fill with the bridge's lights, rooms, switches and motion sensors.

An existing Hue application key can be pasted into **App Key** instead. To build the IP and key into the design file, set the **Bridge IP** and **App Key** properties: they fill the fields whenever the fields are empty at start.

## Slots

Every light, room/zone, switch and motion sensor slot has an **ID** field: the bridge's number for that device. The Setup page lists everything on the bridge with its ID.

- Every empty slot is filled, top down, with the bridge's devices of that kind that aren't already in a slot, in ID order. Entertainment areas are left out of rooms and zones. Raising a count later fills the new rows the same way, and a device added to the bridge lands in the next empty slot.
- Type `-` in an ID field to keep that slot blank: it's never filled.
- Typing an ID shows that device at once. An ID the bridge doesn't have shows *(no light N on the bridge)* (or switch, motion sensor) in the name.

## Controls

Pins are named by slot, e.g. *Light 03 Brightness*, *Group 02 Scene*, *Switch 01 Button 2 Press*, *Motion 01 Presence*, *All Off*. ON buttons read ON or OFF with the light's state.

| Page | Control | Pin | Notes |
|---|---|---|---|
| Lights | ON | both | Toggle. |
| | BRIGHTNESS | both | 0–100 %. **0 % turns the light off**; any value above 0 turns it on at that level. |
| | COLOR TEMP | both | 2000–6500 K. Lights without colour temperature report the bridge's error on Status. |
| | HUE, SAT | both | 0–360°, 0–100 %. Colour lights only. |
| | REACH | output | The bridge can reach the light. |
| | NAME | output | The light's name on the bridge. |
| Rooms & Zones | ON | both | Shows on when any light in the room is on, as the Hue app does. |
| | BRIGHTNESS | both | 0 % turns the room off. |
| | SCENE | both | The bridge's scenes for that room or zone. Picking one, or writing a scene name to the pin, recalls it. Two scenes with the same name show as *Name* and *Name (2)*. |
| | NAME | output | |
| Switches & Sensors | Button 1–4 Press | output | Pulses when that button is pressed and released. |
| | Button 1–4 Hold | output | On while that button is held; off at release. |
| | LAST EVENT | output | e.g. *Button 2 short release*. |
| | BATT, REACH, NAME | output | Battery %, the bridge can reach it, its name. |
| | PRESENCE | output | Motion sensor: someone is there. |
| | LIGHT LUX, TEMP C | output | Motion sensor: light level in lux, temperature in °C. |
| Setup | Online | output | The last poll reached the bridge with a valid key. |
| | Status | output | What the plugin is doing, or the last error. |
| | Refresh | input | Poll and reload scenes now. |
| | All On, All Off | input | Turns every light on the bridge on or off. Every page but About has its own All On / All Off pair at the top (panel only); the Setup pair is the one with pins. |
| About | | | Credits, licence, version. |

## Switches and motion sensors

The plugin reads the bridge's sensors twice a second, so it works with any switch the bridge knows: Hue Dimmer, Smart Button, wall switch module, Tap and the Tap Dial's buttons.

- **Latency:** a press reaches the pin 0–0.5 s after it happens. That suits a button that recalls a scene or starts a macro; it's too slow to feel right for hold-to-dim.
- **Repeats:** the bridge stamps events to the second, so two presses of the same button within one second count as one.
- **The bridge keeps its own rules.** A switch still does whatever the Hue app set it to do. To have a switch drive only Q-SYS, remove its actions in the Hue app.
- **Restarts don't replay:** the last event the bridge holds is shown on Last Event at start, but fires nothing.
- A Hue motion sensor appears on the bridge as three sensors (presence, light level, temperature). Its slot takes the presence sensor's ID; the other two are found automatically.

## Properties

| Property | Default | |
|---|---|---|
| Bridge IP | *empty* | Fills the Bridge IP field when it's empty at start. |
| App Key | *empty* | Fills the App Key field when it's empty at start. |
| Use HTTPS | off | Talk to the bridge over `https://`. Needs the Core to accept the bridge's self-signed certificate. |
| Light Count | 8 | Light slots, 1–32. |
| Group Count | 4 | Room/zone slots, 0–16. 0 removes the Rooms & Zones page. |
| Switch Count | 4 | Switch slots, 0–16. |
| Motion Count | 2 | Motion sensor slots, 0–8. With Switch Count also 0, the Switches & Sensors page is removed and sensors aren't polled. |
| Poll Interval | 3 | Seconds between light and room polls, 1–60. |
| Transition Time | 4 | Fade time for every command, in 100 ms steps (4 = 400 ms, Hue's default). |

## How it talks to the bridge

- **API:** Hue CLIP v1 (`/api/<key>/...`) over HTTP. Every current Hue Bridge serves it, and plain HTTP avoids depending on certificate handling in the Core's HTTP client.
- **Feedback:** polls `/lights` and `/groups` every Poll Interval, `/sensors` every 0.5 s (when there are switch or motion slots), and `/scenes` about once a minute.
- **Pacing:** commands are queued and sent one per 125 ms, with room/zone commands at least 1 s apart, so commands and polls stay inside Hue's published limits. Changes to the same light merge in the queue, so a fader drag sends only its latest value.
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

`structural.py` checks the file as text: balanced blocks, every control and property the runtime uses is declared, no local function called before it's defined, and the `.lua` and `.qplug` are identical. `sim.lua` runs the real plugin under Lua 5.3 against stand-ins for the Q-SYS runtime and a fake Hue Bridge, and checks the layout of every page and the behaviour above. The top of `sim.lua` lists what the stand-ins assume about Q-SYS and the bridge; lines marked UNVERIFIED are the things to confirm on a real Core with a real bridge.

`assets/` holds the SmartSpaces logo; the About page carries it embedded in the plugin.

## License

MIT, copyright (c) 2026 YZ, SmartSpaces. Free to use, change and share, as long as the copyright notice and licence text stay with it. See [LICENSE](LICENSE).

Philips Hue is a trademark of Signify. This plugin is not made, endorsed or supported by Signify.
