import SwiftUI

// MARK: - Knob (turns like a real one)

/// Circle a finger around the knob to turn it (270° = full range), or twist with two fingers.
/// Starting on the centre cap turns it by dragging up/down instead. Double-tap resets.
/// Haptic ticks as it turns; TEMPO clicks per BPM and PITCH clicks into place at x1.00.
struct KnobView: View {
    let spec: KnobSpec
    let model: GasworksModel
    let size: CGFloat

    @State private var dragValue: Double?
    @State private var lastAngle: Double?
    @State private var linearStart: Double?
    @State private var twistBase: Double?
    @State private var tick = 0
    @State private var edgeTick = 0
    @State private var lastDetent = -1
    @State private var turning = false

    private var dialFrame: CGFloat { size * 1.14 }
    private var space: String { "knob-\(spec.id)" }

    var body: some View {
        let value = model.value(spec)
        let span = spec.range.upperBound - spec.range.lowerBound
        let norm = (value - spec.range.lowerBound) / span
        let dial = size * 0.9
        let angle = -135 + 270 * norm

        VStack(spacing: max(3, size * 0.1)) {
            ZStack {
                GKnobScale()
                Circle()
                    .trim(from: 0, to: 0.75 * norm)
                    .stroke(Theme.led, style: StrokeStyle(lineWidth: max(2, size * 0.05), lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(size * 0.1)
                Circle().fill(Color.black.opacity(turning ? 0.34 : 0.26))
                    .frame(width: dial, height: dial)
                    .blur(radius: 2.5).offset(y: size * 0.06)
                GKnobBody(dial: dial)
                    .rotationEffect(.degrees(angle))
                GKnobShine(dial: dial, turning: turning)
            }
            .frame(width: dialFrame, height: dialFrame)
            .coordinateSpace(name: space)

            Text(spec.label)
                .font(GFont.bold(size < 44 ? 10 : 12))
                .tracking(1.2)
                .foregroundStyle(Theme.printSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(spec.format(value))
                .font(GFont.pixel(size < 44 ? 15 : 18))
                .foregroundStyle(turning ? Theme.ledLip : Theme.print)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(rotary(value: value, norm: norm).simultaneously(with: twist(norm: norm)))
        .onTapGesture(count: 2) { model.set(spec, spec.defaultValue) }
        .sensoryFeedback(.selection, trigger: tick)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: edgeTick)
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

    /// `n` is the new 0…1 position.
    private func apply(_ n: Double) {
        let span = spec.range.upperBound - spec.range.lowerBound
        var c = min(1, max(0, n))
        let prev = dragValue.map { min(1, max(0, $0)) } ?? -1
        dragValue = n
        // PITCH clicks into place at x1.00.
        if spec.id == "pitch" {
            let centre = (1 - spec.range.lowerBound) / span
            if abs(c - centre) < 0.025 { c = centre }
        }
        if (c == 0 || c == 1) && c != prev { edgeTick += 1 }
        var v = spec.range.lowerBound + c * span
        if spec.id == "tempo" { v = v.rounded() }
        model.set(spec, v)
        let d: Int = spec.id == "tempo" ? Int(v) : Int(c * 32)
        if d != lastDetent { lastDetent = d; tick += 1 }
    }

    private func rotary(value: Double, norm: Double) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { g in
                guard twistBase == nil else { return }
                turning = true
                let c = Double(dialFrame) / 2
                if dragValue == nil { dragValue = norm; lastDetent = -1 }
                let start = dragValue ?? norm
                // Touches that start on the centre cap (or below the dial) turn by dragging up/down.
                let sx = Double(g.startLocation.x) - c, sy = Double(g.startLocation.y) - c
                if hypot(sx, sy) < Double(size) * 0.2 || Double(g.startLocation.y) > Double(dialFrame) {
                    if linearStart == nil { linearStart = norm }
                    apply((linearStart ?? norm) - Double(g.translation.height) / 160)
                    return
                }
                let dx = Double(g.location.x) - c, dy = Double(g.location.y) - c
                guard hypot(dx, dy) > Double(size) * 0.1 else { return }
                let a = atan2(dy, dx)
                if let last = lastAngle {
                    var d = a - last
                    if d > .pi { d -= 2 * .pi }
                    if d < -.pi { d += 2 * .pi }
                    apply(start + d / (1.5 * .pi))
                }
                lastAngle = a
            }
            .onEnded { _ in lastAngle = nil; linearStart = nil; dragValue = nil; turning = false }
    }

    private func twist(norm: Double) -> some Gesture {
        RotateGesture(minimumAngleDelta: .degrees(1))
            .onChanged { g in
                if twistBase == nil { twistBase = norm; lastAngle = nil; dragValue = norm }
                turning = true
                apply((twistBase ?? norm) + g.rotation.radians / (1.5 * .pi))
            }
            .onEnded { _ in twistBase = nil; dragValue = nil; turning = false }
    }
}

private func gSpoke(_ c: CGPoint, _ a: CGFloat, _ r0: CGFloat, _ r1: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
    p.addLine(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
    return p
}

/// Scale printed on the case around the knob.
struct GKnobScale: View {
    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r0: CGFloat = sz.width / 2 - 1
            let r1: CGFloat = sz.width / 2 - max(3, sz.width * 0.07)
            for i in 0..<11 {
                let t: CGFloat = CGFloat(i) / 10
                let a: CGFloat = (135 + 270 * t) * .pi / 180
                ctx.stroke(gSpoke(c, a, r0, r1), with: .color(Theme.printFaint), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
    }
}

/// The knurled knob and pointer — this part turns.
struct GKnobBody: View {
    let dial: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.capHi, Theme.capLip], startPoint: .top, endPoint: .bottom))
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r0: CGFloat = sz.width / 2 - 0.5
                let r1: CGFloat = sz.width / 2 - max(2.5, sz.width * 0.09)
                let n = sz.width < 40 ? 24 : 32
                for i in 0..<n {
                    let a: CGFloat = CGFloat(i) / CGFloat(n) * 2 * .pi
                    ctx.stroke(gSpoke(c, a, r0, r1), with: .color(Color.white.opacity(0.16)), lineWidth: 1.2)
                    ctx.stroke(gSpoke(c, a + .pi / CGFloat(n), r0, r1), with: .color(Color.black.opacity(0.5)), lineWidth: 1)
                }
            }
            Circle().fill(LinearGradient(colors: [Color(hex: 0x50534A), Theme.cap], startPoint: .top, endPoint: .bottom))
                .padding(dial * 0.13)
            VStack(spacing: 0) {
                Capsule().fill(Theme.rubber).frame(width: max(2.5, dial * 0.07), height: dial * 0.27)
                Spacer(minLength: 0)
            }
            .padding(.top, dial * 0.06)
        }
        .frame(width: dial, height: dial)
    }
}

/// Light from above that stays put while the knob turns.
struct GKnobShine: View {
    let dial: CGFloat
    let turning: Bool
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.2), .clear], center: UnitPoint(x: 0.35, y: 0.25),
                                         startRadius: 0, endRadius: dial * 0.55))
            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1).scaleEffect(turning ? 1.04 : 1)
        }
        .frame(width: dial, height: dial)
        .allowsHitTesting(false)
    }
}

// MARK: - Pad (soft rubber pad sitting in a recessed well)

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
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let glow = lit || pressed

        ZStack {
            // The well cut into the case.
            shape
                .fill(Theme.bodyRing.shadow(.inner(color: .black.opacity(0.38), radius: 3, x: 0, y: 2.5))
                    .shadow(.inner(color: .white.opacity(0.35), radius: 0.5, x: 0, y: -1)))
                .padding(large ? -4 : -3)

            ZStack(alignment: .topLeading) {
                GPadSurface(radius: radius, large: large, pressed: pressed,
                            top: glow || selected ? Theme.rubberLit : Theme.rubber,
                            low: glow || selected ? Theme.rubberLitLo : Theme.rubberLo,
                            ring: selected ? fam.opacity(0.85) : nil)

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
            }
            .scaleEffect(pressed ? 0.965 : 1)
            .offset(y: pressed ? 1.5 : 0)
        }
        .animation(.spring(response: 0.14, dampingFraction: 0.6), value: pressed)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The soft, domed rubber surface of a pad. It darkens and squashes when pressed.
struct GPadSurface: View {
    let radius: CGFloat
    let large: Bool
    let pressed: Bool
    let top: Color
    let low: Color
    let ring: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let hiOpacity: Double = pressed ? 0.35 : 0.95
        let hiRadius: CGFloat = pressed ? 1 : 1.6
        let hiY: CGFloat = pressed ? 0.5 : 2
        let loOpacity: Double = pressed ? 0.24 : 0.12
        let loRadius: CGFloat = pressed ? 7 : 4
        let loY: CGFloat = pressed ? 3 : -3
        let dropOpacity: Double = pressed ? 0.1 : 0.3
        let dropRadius: CGFloat = pressed ? 0.5 : 2.5
        let dropY: CGFloat = pressed ? 0.5 : 3
        let dishOpacity: Double = pressed ? 0.07 : 0.035
        let inset: CGFloat = large ? 9 : 6
        let dishR: CGFloat = large ? 80 : 50
        let gradient = LinearGradient(colors: [top, low], startPoint: .top, endPoint: .bottom)
        let style = gradient
            .shadow(.inner(color: Color.white.opacity(hiOpacity), radius: hiRadius, x: 0, y: hiY))
            .shadow(.inner(color: Color.black.opacity(loOpacity), radius: loRadius, x: 0, y: loY))

        return shape
            .fill(style)
            .overlay {
                shape.inset(by: inset)
                    .fill(RadialGradient(colors: [Color.black.opacity(dishOpacity), Color.clear],
                                         center: .center, startRadius: 0, endRadius: dishR))
            }
            .overlay {
                if let ring { shape.strokeBorder(ring, lineWidth: 2) }
            }
            .shadow(color: Color.black.opacity(dropOpacity), radius: dropRadius, x: 0, y: dropY)
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
