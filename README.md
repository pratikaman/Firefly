<h1 align="center">Firefly</h1>
<p align="center"><b>Your keyboard backlight, on autopilot.</b></p>

Firefly pays attention to two things: where the sun is where you are, and how much
light is actually falling on your Mac. Then it sets the keyboard backlight to match.

- **Sunny afternoon, bright desk** — off. You weren't going to see it anyway.
- **Evening, lamp on** — just a little glow.
- **Dark room at 2am** — all of it.

Reach for the brightness keys yourself and it takes the hint: it backs off for a
while, then quietly picks the job back up.

Click the menu bar icon if you want to fiddle — how bright it's allowed to get, how
much the sun gets a say, and two buttons to teach it what *dark* and *bright* mean
in your room.

Lives in the menu bar. No dock icon, no network, no fuss.

Needs an Apple Silicon Mac with a backlit keyboard.

## Install

### Option 1: Let an agent do it

Paste this into Claude Code (or any coding agent):

> Clone https://github.com/pratikaman/Firefly, run `./build.sh --install`, and launch ~/Applications/Firefly.app

### Option 2: Build it yourself

```sh
git clone https://github.com/pratikaman/Firefly.git
cd Firefly
./build.sh --install   # builds Firefly.app and installs it to ~/Applications
open ~/Applications/Firefly.app
```

Built entirely on vibes.
