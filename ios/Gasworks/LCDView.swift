import SwiftUI

/// The amber screen: a pixel mascot that puffs on every hit, the current sound or knob value,
/// and a live oscilloscope of the output.
struct LCDView: View {
    let model: GasworksModel
    var large = false
    @State private var field = PuffField()

    var body: some View {
        let preset = Presets.all[model.lastHitPreset]
        let channel = model.tracks.firstIndex { $0.preset == preset.id }
        let topLeft = "PAD \(String(format: "%02d", preset.id + 1))" + (channel.map { " · CH\($0 + 1)" } ?? "")
        let topRight = model.isPlaying
            ? "PLAYING · STEP \(String(format: "%02d", max(0, model.currentStep) + 1))"
            : "\(Int(model.tempo)) BPM"

        VStack(alignment: .leading, spacing: large ? 6 : 4) {
            HStack {
                Text(topLeft)
                Spacer(minLength: 4)
                Text(topRight)
            }
            .font(GFont.pixel(large ? 19 : 16))
            .foregroundStyle(Theme.lcdMid)
            .lineLimit(1)

            HStack(alignment: .bottom, spacing: large ? 14 : 10) {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        field.draw(in: &ctx, size: size, now: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                .frame(width: large ? 118 : 76)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.flashText ?? preset.name.uppercased())
                        .font(GFont.pixel(large ? 42 : 32))
                        .foregroundStyle(Theme.lcd)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if large {
                        Text(detail(for: preset))
                            .font(GFont.pixel(18))
                            .foregroundStyle(Theme.lcdMid)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    ScopeView(model: model)
                        .frame(height: large ? 30 : 24)
                }
            }
        }
        .padding(.horizontal, large ? 14 : 12)
        .padding(.vertical, large ? 12 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.lcdBg)
        .overlay(Scanlines().allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: large ? 10 : 9, style: .continuous))
        .padding(large ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: large ? 18 : 16, style: .continuous)
                .fill(Theme.cap)
                .shadow(color: .white.opacity(0.3), radius: 0, y: 2)
        )
        .onChange(of: model.hitTick) {
            field.spawn(duration: Presets.all[model.lastHitPreset].dur, now: Date().timeIntervalSinceReferenceDate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screen")
        .accessibilityValue("\(preset.name). \(topRight)")
    }

    private func detail(for p: FartPreset) -> String {
        if p.f0 == 0 { return "BUBBLES · \(p.bubbles) BLIPS" }
        let wave = p.squeak ? "SAW+TRI" : "SAW"
        return "\(wave) · FLUTTER \(Int(p.flutter))HZ"
    }
}

struct ScopeView: View {
    let model: GasworksModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            Canvas { ctx, size in
                let samples = model.scopeSamples(256)
                var path = Path()
                for (i, s) in samples.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(max(1, samples.count - 1))
                    let y = size.height / 2 - CGFloat(s) * size.height * 0.48
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(Theme.lcdMid), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                y += 3
            }
        }
    }
}

/// Mascot + gas clouds, simulated in screen-pixel units.
final class PuffField {
    struct Puff {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, r: CGFloat
        var life: CGFloat
        var born: TimeInterval
    }

    private static let mascot: [String] = [
        "................", ".....kkkkkk.....", "...kkbbbbbbkk...", "..kbbbbbbbbbbk..",
        ".kbbbbbbbbbbbbk.", ".kbbbbbbkbbkbbk.", "kbbbbbbbkbbkbbbk", "kbbbbbbbbbbbbbbk",
        "kbbbbbbccbbbccbk", "kbbbbbbbbkkkbbbk", ".kbbbbbbbbbbbbk.", ".kbbbbbbbbbbbbk.",
        "..kkbbbbbbbbkk..", "....kkkkkkkk....", "....kk....kk....", "....kk....kk....",
    ]

    private var puffs: [Puff] = []
    private var squashUntil: TimeInterval = 0
    private var blushUntil: TimeInterval = 0
    private var last: TimeInterval = 0

    func spawn(duration: Double, now: TimeInterval) {
        squashUntil = now + 0.13
        blushUntil = now + 0.5
        let n = Int(3 + min(10, duration * 6))
        let gap = min(0.06, duration * 0.09)
        for i in 0..<n {
            puffs.append(Puff(x: 0, y: 0,
                              vx: -(0.25 + CGFloat.random(in: 0...0.6)),
                              vy: -CGFloat.random(in: 0...0.25),
                              r: 1 + CGFloat.random(in: 0...3.2),
                              life: 1,
                              born: now + Double(i) * gap))
        }
        if puffs.count > 80 { puffs.removeFirst(puffs.count - 80) }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        let steps = last == 0 ? 1 : min(4, max(0, (now - last) * 60))
        last = now

        // One "screen pixel" — the mascot is 16 of them tall.
        let px = max(1, floor(min(size.height * 0.8, size.width * 0.66) / 16))
        let mascotW = px * 16
        let ox = size.width - mascotW - px
        let groundY = size.height - px * 2
        let squash: CGFloat = now < squashUntil ? px : 0
        let oy = groundY - mascotW + squash

        // ground
        var x: CGFloat = 0
        while x < size.width {
            ctx.fill(Path(CGRect(x: x, y: groundY + px, width: px, height: max(1, px / 2))), with: .color(Theme.lcdDim))
            x += px * 2
        }

        // puffs drift left out of the mascot's back end
        let originX = ox + px * 1.5
        let originY = oy + px * 10
        for i in puffs.indices {
            guard now >= puffs[i].born else { continue }
            if puffs[i].x == 0 && puffs[i].y == 0 {
                puffs[i].x = originX + CGFloat.random(in: 0...(px * 2))
                puffs[i].y = originY + CGFloat.random(in: 0...(px * 3))
            }
            let s = CGFloat(steps)
            puffs[i].x += puffs[i].vx * px * 0.5 * s
            puffs[i].y += puffs[i].vy * px * 0.5 * s
            puffs[i].r += 0.04 * s
            puffs[i].life -= 0.012 * s
        }
        puffs.removeAll { $0.life <= 0 }
        for p in puffs where now >= p.born {
            let color = p.life > 0.55 ? Theme.lcdMid : Theme.lcdDim
            let r = Int(p.r.rounded())
            for yy in -r...r {
                for xx in -r...r where xx * xx + yy * yy <= r * r {
                    let cx = (p.x / px).rounded() * px + CGFloat(xx) * px * 0.5
                    let cy = (p.y / px).rounded() * px + CGFloat(yy) * px * 0.5
                    ctx.fill(Path(CGRect(x: cx, y: cy, width: px * 0.5, height: px * 0.5)), with: .color(color))
                }
            }
        }

        // mascot
        let blush = now < blushUntil
        for (row, line) in Self.mascot.enumerated() {
            if squash > 0 && row >= 14 { continue }
            for (col, ch) in line.enumerated() {
                let color: Color
                switch ch {
                case "k": color = Theme.lcd
                case "b": color = Theme.lcdBody
                case "c": color = blush ? Theme.lcd : Theme.lcdMid
                default: continue
                }
                let yOff: CGFloat = (squash > 0 && row > 12) ? -px : 0
                ctx.fill(Path(CGRect(x: ox + CGFloat(col) * px, y: oy + CGFloat(row) * px + yOff, width: px, height: px)),
                         with: .color(color))
            }
        }
    }
}
