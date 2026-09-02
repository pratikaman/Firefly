# Firefly

A menu bar app that runs the keyboard backlight off two signals: **where the sun is**
at your location, and **how much light is actually hitting the Mac**.

Apple Silicon only (it uses the AOP ambient light sensor and CoreBrightness).

## The idea

The sensor is the base, and a dark sky only ever *adds* glow on top of it:

```
target = roomNeed + glow · (1 - roomNeed)      roomNeed = how dark the room is
glow   = 0.30 · (how dark it is outside)
```

In daylight `glow` is zero, so this collapses to trusting the sensor alone. After dark
it lifts the whole curve:

| situation | backlight |
|---|---|
| sunny 2pm, bright desk | **0%** — off, it's pointless |
| dark room at 2pm | **100%** — blackout curtains still need light |
| evening, but a bright lamp | **16%** — a little glow |
| night, dark room | **100%** — full |

**Why not average the two signals?** The first version did
(`0.70·room + 0.30·outside`) and it had the sun *subtracting* from a dark daytime room:
blackout curtains at noon got 70% instead of 100%, dimming keys you still couldn't see.
A screen blend fixes that — glow fills the headroom the room leaves, so it can lift a
bright room off zero but never pull a dark one down.

**Why keep the sun at all?** Because the sensor alone cannot tell 800 lux at 2pm from
800 lux at 10pm, and those want different answers. Sun glow is the only thing that
produces the evening-lamp case. Slide *Sun glow* to zero in the UI for pure sensor
behaviour.

## How it reads the world

**Ambient light.** The Intel-era `AppleLMUController` is gone on Apple Silicon. The
sensor is now an HID service (usage page `0xFF00`, usage `4`, product `als`, driven by
`AppleSPUVD6286`). Firefly reads the HID event's level, falls back to the driver's
`CurrentLux`, and below ~2 lux — where both bottom out and stop resolving — derives lux
from the raw channels instead.

The counts-to-lux factor (`0.0366`) was measured on this hardware, sweeping a phone
torch from a covered sensor up to ~870 lux. The ratio held between 0.0351 and 0.0382
across the whole range, which is linear enough that one constant beats a fitted curve.

**The sun.** Pure NOAA solar-position arithmetic — no network, no almanac. It returns
the sun's elevation, which beats clock time outright: 7pm is broad daylight in June and
long dark in December.

**The keyboard.** `KeyboardBrightnessClient` from the private CoreBrightness framework.
Firefly also switches off macOS's own ambient keyboard dimming while it runs, because
two controllers on one backlight just fight each other.

## Behaviour

- **Smooth ramp.** Target is recomputed every 4s; the backlight eases toward it in
  small steps, so it reads as ambience rather than a light switch.
- **Manual override.** Touch F5/F6 and Firefly notices the backlight isn't where it
  left it, stands down for 20 minutes, then quietly resumes. "Resume auto" skips the wait.
- **Calibration.** The two buttons teach it your room: tap *This is dark* in the dark and
  *This is bright* in the light. The live lux and raw counts are shown, so you can watch
  the sensor respond in real time.
- **Location.** CoreLocation, asked once. Denied or unavailable, it falls back to manual
  coordinates; with neither it assumes civil twilight and leans on the sensor alone.

## Build

```sh
./build.sh            # -> build/Firefly.app
./build.sh --install  # -> ~/Applications/Firefly.app
```

## A note on the sensor

`AmbientLight` holds the `IOHIDEventSystemClient` and the services array for its whole
lifetime, not just the one service. The service clients are owned by the client, and the
array owns the elements `CopyServices` hands out. Keeping only the service leaves a
dangling pointer that `IOHIDServiceClientCopyEvent` will dereference — which reads fine
from a terminal and kills the process under LaunchServices. Don't "tidy" those away.
