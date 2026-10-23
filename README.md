# Gasworks G-1

A sixteen-voice flatulence synthesizer that runs in your browser.

Hit the pads, twist the knobs, program a beat. Every sound is synthesized live with the Web Audio API — no samples, so no two toots are exactly alike.

## Features

- **16 sound pads** — Classic, Squeaker, Tuba, Wet Slap, Machine Gun, Long Haul, Balloon, Silent Deadly, Duck, Rumble, Stutter, Bathtub, Riser, Faller, Whoopee, Tiny Toot
- **Effects knobs** — Reverb, Delay, Delay Time, Repeats, Pitch, Drive, Tempo, Volume
- **Pixel LCD** — an animated mascot that puffs with every hit, plus a live waveform scope
- **4-channel step sequencer and mixer** — 16 steps per channel, with per-channel sound, volume and mute
- **Shuffle** for random beats, **Clear** to start fresh; your pattern is saved in your browser

## Controls

| Input | Action |
| --- | --- |
| `1 2 3 4` / `Q W E R` / `A S D F` / `Z X C V` | Play the 16 pads |
| `Space` | Play / stop the sequencer |
| Drag a knob up or down (or scroll, or arrow keys) | Adjust it |
| Double-click a knob | Reset to default |

## How the sounds are made

Each voice is a pitch-gliding sawtooth oscillator, randomly detuned for wobble, run through a lowpass filter. A fast, irregular amplitude "flutter" gives it the characteristic *brrrt*. Band-passed noise adds breath and wetness, a triangle layer adds squeak, and short rising sine blips make bubbles. The mix then goes through a convolution reverb, a feedback delay, and a tanh drive stage.

## iPhone & iPad app

`ios/` holds a native SwiftUI version — one screen, laid out for the device it's on:

- **iPhone (portrait):** screen, 8 knobs, 16 pads and a 4-channel sequencer that pages through steps 1–8 / 9–16. Each channel chip is also its mixer strip: tap to mute, slide sideways for level, long-press to pick the sound or solo it.
- **iPad (landscape):** big screen and a 2×4 knob bank, large pads, a mixer with faders plus mute/solo, and all 16 steps on view. iPad portrait and Split View use the tall layout with all 16 steps.

The audio engine is written from scratch on `AVAudioEngine`: every voice is synthesized in a real-time render callback, the sequencer is sample-accurate (it runs inside the audio thread, not on a timer), and reverb and delay are Apple's built-in audio units. It plays with the silent switch on and mixes with whatever music is already playing.

### Build

Requirements: Xcode 16 or newer, iOS 17+.

1. Open `ios/Gasworks.xcodeproj`.
2. Select the **Gasworks** target → *Signing & Capabilities* → choose your Team (change the bundle ID `com.sixthneo.gasworks` if it's taken).
3. Pick an iPhone or iPad (a real device sounds best) and press **Run**.

From the command line:

```sh
cd ios
xcodebuild -project Gasworks.xcodeproj -scheme Gasworks -destination 'generic/platform=iOS Simulator' build
```

### Layout of the code

| File | What it does |
| --- | --- |
| `SynthCore.swift` | Real-time DSP: voices, bubbles, flutter, filters, drive, sequencer, lock-free-ish UI hand-off |
| `AudioEngine.swift` | Audio session, `AVAudioSourceNode` → delay → reverb, interruption handling |
| `Presets.swift` | The 16 sound recipes, grouped by family |
| `GasworksModel.swift` | App state, knob specs, sequencer/mixer actions, save/restore |
| `Layouts.swift` | iPhone tall layout and iPad wide layout |
| `Controls.swift` | Knob, pad, step, channel chip, fader, play button |
| `LCDView.swift` | Amber screen with the pixel mascot, gas puffs and oscilloscope |

## Run the web version

It's a single static file with no build step and no dependencies (fonts come from Google Fonts).

```sh
open index.html
# or serve it
npx serve .
```

## Deploy

Any static host works: GitHub Pages (Settings → Pages → deploy from `main`), Netlify, Vercel, or Cloudflare Pages.

## Credits

Fonts: [VT323](https://fonts.google.com/specimen/VT323) and [Barlow Condensed](https://fonts.google.com/specimen/Barlow+Condensed), both under the SIL Open Font License.
