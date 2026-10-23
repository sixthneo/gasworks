import SwiftUI

// MARK: - Knob

/// Drag up or down to turn. Double-tap resets. VoiceOver can swipe up/down to adjust.
struct KnobView: View {
    let spec: KnobSpec
    let model: GasworksModel
    let size: CGFloat
    @State private var dragStart: Double?

    var body: some View {
        let value = model.value(spec)
        let span = spec.range.upperBound - spec.range.lowerBound
        let norm = (value - spec.range.lowerBound) / span

        VStack(spacing: max(3, size * 0.1)) {
            ZStack {
                Circle().fill(Theme.bodyRing)
                    .frame(width: size + size * 0.14, height: size + size * 0.14)
                Circle().fill(Color(hex: 0x1A1B18))
                    .frame(width: size, height: size)
                    .offset(y: size * 0.07)
                Circle()
                    .fill(RadialGradient(colors: [Theme.capHi, Theme.cap],
                                         center: UnitPoint(x: 0.4, y: 0.3),
                                         startRadius: 0, endRadius: size * 0.62))
                    .frame(width: size, height: size)
                VStack(spacing: 0) {
                    Capsule().fill(Theme.rubber)
                        .frame(width: max(2.5, size * 0.065), height: size * 0.3)
                    Spacer(minLength: 0)
                }
                .padding(.top, size * 0.08)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-135 + 270 * norm))
            }
            .frame(width: size + size * 0.14, height: size + size * 0.14)

            Text(spec.label)
                .font(GFont.bold(size < 44 ? 10 : 12))
                .tracking(1.2)
                .foregroundStyle(Theme.printSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(spec.format(value))
                .font(GFont.pixel(size < 44 ? 15 : 18))
                .foregroundStyle(Theme.print)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { g in
                    if dragStart == nil { dragStart = value }
                    model.set(spec, (dragStart ?? value) - Double(g.translation.height) / 160 * span)
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture(count: 2) { model.set(spec, spec.defaultValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.label.capitalized)
        .accessibilityValue(spec.format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.set(spec, value + span / 20, flash: false)
            case .decrement: model.set(spec, value - span / 20, flash: false)
            @unknown default: break
            }
        }
    }
}

// MARK: - Pad

/// Fires on touch-down (not on release) so it feels like an instrument. Several pads can be held at once.
struct PadButton: View {
    let preset: FartPreset
    let model: GasworksModel
    var large = false
    @State private var pressed = false
    @State private var taps = 0

    var body: some View {
        let lit = model.litPads.contains(preset.id)
        let selected = model.selectedPad == preset.id
        let fam = Theme.family(preset.family)
        let radius: CGFloat = large ? 14 : 11
        let depth: CGFloat = large ? 5 : 4

        VStack(alignment: .leading, spacing: 4) {
            Text(preset.name.uppercased())
                .font(GFont.semi(large ? 17 : 13))
                .tracking(0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if large {
                    Text(preset.family.label)
                        .font(GFont.semi(11))
                        .tracking(1.5)
                        .foregroundStyle(Theme.printFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(fam)
                    .frame(width: large ? 10 : 8, height: large ? 10 : 8)
                    .opacity(lit || selected ? 1 : 0.55)
                    .shadow(color: lit ? fam : .clear, radius: 5)
                    .overlay(Circle().fill(Color.white.opacity(lit ? 0.5 : 0)).frame(width: 3, height: 3))
            }
        }
        .foregroundStyle(Theme.print)
        .padding(.horizontal, large ? 12 : 8)
        .padding(.top, large ? 12 : 7)
        .padding(.bottom, large ? 10 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: selected || pressed ? [Theme.rubberLit, Theme.rubberLitLo] : [Theme.rubber, Theme.rubberLo],
                                     startPoint: .top, endPoint: .bottom))
        )
        .offset(y: pressed ? depth - 1 : 0)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.rubberLip)
                .offset(y: depth)
                .shadow(color: .black.opacity(pressed ? 0.1 : 0.2), radius: pressed ? 2 : 6, y: pressed ? 1 : 4)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    taps += 1
                    model.hit(preset.id)
                }
                .onEnded { _ in pressed = false }
        )
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: taps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preset.name)
        .accessibilityHint("Plays the sound")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.hit(preset.id) }
    }
}

struct PadGrid: View {
    let model: GasworksModel
    var large = false
    var spacing: CGFloat = 8

    var body: some View {
        VStack(spacing: spacing + (large ? 4 : 2)) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<4, id: \.self) { col in
                        PadButton(preset: Presets.all[row * 4 + col], model: model, large: large)
                    }
                }
            }
        }
        .padding(.bottom, large ? 5 : 4)
    }
}

// MARK: - Sequencer step

struct StepCell: View {
    let track: Int
    let step: Int
    let model: GasworksModel
    let height: CGFloat

    var body: some View {
        let t = model.tracks[track]
        let on = t.steps[step]
        let now = model.currentStep == step
        let audible = model.isAudible(track: track)
        let fill: Color = on ? (audible ? Theme.color(forPreset: t.preset) : Theme.stepMuted)
                             : (step % 4 == 0 ? Theme.stepBeat : Theme.stepOff)

        Button {
            model.toggleStep(track: track, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? Color.black.opacity(0.3) : Theme.bodyRing)
                        .offset(y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.print, lineWidth: 2)
                        .padding(-3)
                        .opacity(now ? 1 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(now && on ? 0.35 : 0))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Channel \(track + 1), step \(step + 1)")
        .accessibilityValue(on ? "On" : "Off")
    }
}

// MARK: - Sound picker

/// Menu content listing all 16 sounds, grouped by family.
struct SoundMenuItems: View {
    let track: Int
    let model: GasworksModel

    var body: some View {
        ForEach(SoundFamily.allCases, id: \.self) { fam in
            Section(fam.label) {
                ForEach(Presets.all.filter { $0.family == fam }) { p in
                    Button {
                        model.setPreset(track: track, preset: p.id)
                    } label: {
                        if p.id == model.tracks[track].preset {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - iPhone channel chip

/// Tap = mute. Slide sideways = level. Long-press = pick sound or solo.
struct ChannelChip: View {
    let track: Int
    let model: GasworksModel
    let width: CGFloat
    let height: CGFloat
    @State private var dragStart: Double?

    var body: some View {
        let t = model.tracks[track]
        let audible = model.isAudible(track: track)
        let color = Theme.color(forPreset: t.preset)
        let status = t.solo ? " · SOLO" : (t.muted ? " · MUTED" : "")

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.rubber)
            Rectangle()
                .fill(audible ? color.opacity(0.3) : Color(hex: 0xD6CFBD))
                .frame(width: width * CGFloat(t.volume))
            VStack(alignment: .leading, spacing: 1) {
                Text("CH\(track + 1)\(status)")
                    .font(GFont.bold(10))
                    .tracking(1)
                    .foregroundStyle(t.solo ? Theme.ledLip : Theme.printFaint)
                Text(Presets.all[t.preset].name.uppercased())
                    .font(GFont.semi(height > 40 ? 15 : 13))
                    .foregroundStyle(audible ? Theme.print : Theme.printFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 7)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.rubberLip).offset(y: 2))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { g in
                    if dragStart == nil { dragStart = t.volume }
                    model.setVolume(track: track, (dragStart ?? t.volume) + Double(g.translation.width / width))
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture { model.toggleMute(track: track) }
        .contextMenu {
            SoundMenuItems(track: track, model: model)
            Section {
                Button(t.solo ? "Unsolo" : "Solo", systemImage: "headphones") { model.toggleSolo(track: track) }
                Button(t.muted ? "Unmute" : "Mute", systemImage: t.muted ? "speaker.wave.2" : "speaker.slash") {
                    model.toggleMute(track: track)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Channel \(track + 1), \(Presets.all[t.preset].name)\(t.muted ? ", muted" : "")\(t.solo ? ", solo" : "")")
        .accessibilityValue("Level \(Int(t.volume * 100)) percent")
        .accessibilityHint("Double-tap to mute. Swipe up or down to change level.")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: model.setVolume(track: track, t.volume + 0.05)
            case .decrement: model.setVolume(track: track, t.volume - 0.05)
            @unknown default: break
            }
        }
        .accessibilityAction { model.toggleMute(track: track) }
    }
}

// MARK: - iPad fader

struct VerticalFader: View {
    let track: Int
    let model: GasworksModel

    var body: some View {
        GeometryReader { geo in
            let t = model.tracks[track]
            let capH: CGFloat = 26
            let travel = max(1, geo.size.height - capH)
            let v = CGFloat(t.volume)
            let color = model.isAudible(track: track) ? Theme.color(forPreset: t.preset) : Theme.printFaint

            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.cap).frame(width: 6)
                Capsule().fill(color).frame(width: 6, height: travel * v + capH / 2)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.rubber, Theme.rubberLo], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(Theme.print).frame(height: 2).padding(.horizontal, 9))
                    .frame(width: min(44, geo.size.width), height: capH)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.rubberLip).offset(y: 3))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
                    .offset(y: -travel * v)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let nv = 1 - (g.location.y - capH / 2) / travel
                        model.setVolume(track: track, Double(nv))
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Channel \(track + 1) level")
        .accessibilityValue("\(Int(model.tracks[track].volume * 100)) percent")
        .accessibilityAdjustableAction { dir in
            let v = model.tracks[track].volume
            switch dir {
            case .increment: model.setVolume(track: track, v + 0.05)
            case .decrement: model.setVolume(track: track, v - 0.05)
            @unknown default: break
            }
        }
    }
}

// MARK: - Transport

struct PlayButton: View {
    let model: GasworksModel
    var width: CGFloat = 76
    var height: CGFloat = 44
    var fontSize: CGFloat = 15

    var body: some View {
        Button(action: model.togglePlay) {
            HStack(spacing: 6) {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: fontSize - 2, weight: .bold))
                Text(model.isPlaying ? "STOP" : "PLAY")
                    .font(GFont.bold(fontSize))
                    .tracking(1.5)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(HardButtonStyle(fill: model.isPlaying ? Theme.red : Theme.led,
                                     lip: model.isPlaying ? Theme.redLip : Theme.ledLip,
                                     foreground: model.isPlaying ? .white : Theme.cap,
                                     depth: 4))
        .sensoryFeedback(.selection, trigger: model.isPlaying)
        .accessibilityLabel(model.isPlaying ? "Stop" : "Play")
    }
}
