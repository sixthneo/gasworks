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

## Run it

It's a single static file with no build step and no dependencies (fonts come from Google Fonts).

```sh
open index.html
# or serve it
npx serve .
```

## Deploy

Any static host works: GitHub Pages (Settings → Pages → deploy from `main`), Netlify, Vercel, or Cloudflare Pages.
