import SwiftUI

// MARK: - Root

struct RootView: View {
    let model: GasworksModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > size.height && size.width >= 900 {
                WideLayout(model: model, size: size)
            } else {
                TallLayout(model: model, size: size)
            }
        }
        .background(CaseBackground().ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.save() }
        }
    }
}

// MARK: - Shared pieces

struct Wordmark: View {
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("GASWORKS ") + Text("G-1").foregroundColor(Theme.ledLip))
                .font(GFont.bold(large ? 30 : 22))
                .tracking(large ? 5 : 3.5)
                .foregroundColor(Theme.print)
            Text(large ? "ANALOG-ISH WIND SYNTHESIS · 16 VOICES · 4 CH" : "16-VOICE WIND SYNTH")
                .font(GFont.semi(large ? 13 : 11))
                .tracking(2)
                .foregroundStyle(Theme.printSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

struct KnobRow: View {
    let specs: [KnobSpec]
    let model: GasworksModel
    let size: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(specs) { KnobView(spec: $0, model: model, size: size) }
        }
    }
}

struct KnobGrid: View {
    let specs: [KnobSpec]
    let model: GasworksModel
    let size: CGFloat

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 14) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(specs[(row * 4)..<(row * 4 + 4)]) { KnobView(spec: $0, model: model, size: size) }
                }
            }
        }
    }
}

// MARK: - Tall layout (iPhone, iPad portrait, iPad split view)

struct TallLayout: View {
    let model: GasworksModel
    let size: CGSize

    var body: some View {
        let W = size.width, H = size.height
        let roomy = W >= 600
        let side: CGFloat = roomy ? 28 : 16
        let inner = W - side * 2
        let spacing: CGFloat = H > 900 ? 18 : 12
        let headerH: CGFloat = roomy ? 56 : 44
        let knobSize = min(56, max(30, inner / 8 - 12))
        let knobBlockH = knobSize * 1.14 + (knobSize < 44 ? 34 : 40)
        let lcdH = min(roomy ? 190 : 150, max(106, H * 0.135))
        let rest = max(200, H - headerH - lcdH - knobBlockH - spacing * 4 - 8)
        let padsH = rest * 0.55
        let seqH = rest - padsH

        VStack(spacing: spacing) {
            header(height: headerH, roomy: roomy)
            LCDView(model: model, large: roomy)
                .frame(height: lcdH)
            KnobRow(specs: KnobSpec.phoneSet, model: model, size: knobSize)
                .frame(height: knobBlockH)
            PadGrid(model: model, large: roomy, spacing: roomy ? 12 : 8)
                .frame(height: padsH)
            TallSequencer(model: model, allSteps: roomy, height: seqH, width: inner)
                .frame(height: seqH)
        }
        .padding(.horizontal, side)
        .padding(.top, 4)
        .frame(width: W, height: H, alignment: .top)
    }

    private func header(height: CGFloat, roomy: Bool) -> some View {
        HStack(spacing: 8) {
            Wordmark(large: roomy)
            Spacer(minLength: 8)
            Button(action: model.shuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HardButtonStyle())
            .accessibilityLabel("Shuffle beat")
            PlayButton(model: model, width: roomy ? 110 : 80, height: 44, fontSize: roomy ? 17 : 15)
        }
        .frame(height: height)
    }
}

struct TallSequencer: View {
    let model: GasworksModel
    let allSteps: Bool
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        let headerH: CGFloat = 30
        let rowGap: CGFloat = 6
        let rowH = max(26, min(allSteps ? 76 : 56, (height - 20 - headerH - rowGap * 4) / 4))
        let chipW: CGFloat = allSteps ? 130 : 76
        let range = allSteps ? 0..<16 : (model.stepPage * 8)..<(model.stepPage * 8 + 8)

        VStack(spacing: rowGap) {
            HStack(spacing: 8) {
                if allSteps {
                    Text("SEQUENCER")
                        .font(GFont.bold(12)).tracking(2.4)
                        .foregroundStyle(Theme.printSoft)
                } else {
                    PageSwitch(model: model)
                }
                Spacer(minLength: 4)
                Text(allSteps ? "TAP CH = MUTE · SLIDE = LEVEL · HOLD = SOUND" : "HOLD CH = SOUND")
                    .font(GFont.semi(11)).tracking(1)
                    .foregroundStyle(Theme.printFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button(action: model.clear) {
                    Text("CLEAR").font(GFont.bold(12)).tracking(1.2)
                        .padding(.horizontal, 10).frame(height: 28)
                }
                .buttonStyle(OutlineButtonStyle(radius: 8))
            }
            .frame(height: headerH)

            ForEach(0..<4, id: \.self) { t in
                HStack(spacing: 6) {
                    ChannelChip(track: t, model: model, width: chipW, height: rowH)
                    HStack(spacing: allSteps ? 5 : 4) {
                        ForEach(Array(range), id: \.self) { s in
                            StepCell(track: t, step: s, model: model, height: rowH)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WellBackground())
    }
}

struct PageSwitch: View {
    let model: GasworksModel

    var body: some View {
        let playingPage = model.currentStep < 0 ? -1 : model.currentStep / 8
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { page in
                let selected = model.stepPage == page
                Button {
                    model.stepPage = page
                } label: {
                    HStack(spacing: 4) {
                        Text(page == 0 ? "1–8" : "9–16")
                            .font(GFont.bold(12)).tracking(1.2)
                        Circle()
                            .fill(Theme.led)
                            .frame(width: 5, height: 5)
                            .opacity(playingPage == page ? 1 : 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .foregroundStyle(selected ? Theme.rubber : Theme.print)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Theme.cap : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.bodyRing))
    }
}

// MARK: - Wide layout (iPad landscape)

struct WideLayout: View {
    let model: GasworksModel
    let size: CGSize

    var body: some View {
        let W = size.width, H = size.height
        let side: CGFloat = 28
        let headerH: CGFloat = 56
        let spacing: CGFloat = 18
        let avail = H - headerH - spacing * 2 - 16
        let midH = avail * 0.6
        let seqH = avail - midH
        let leftW = min(370, W * 0.29)
        let mixerW = min(270, W * 0.21)
        let knobSize = min(56, max(40, leftW / 4 - 30))

        VStack(spacing: spacing) {
            header.frame(height: headerH)
            HStack(alignment: .top, spacing: 22) {
                VStack(spacing: 16) {
                    LCDView(model: model, large: true)
                        .frame(height: midH * 0.47)
                    KnobGrid(specs: KnobSpec.padSet, model: model, size: knobSize)
                }
                .frame(width: leftW)
                PadGrid(model: model, large: true, spacing: 12)
                    .frame(maxWidth: .infinity)
                MixerPanel(model: model)
                    .frame(width: mixerW)
            }
            .frame(height: midH)
            WideSequencer(model: model)
                .frame(height: seqH)
        }
        .padding(.horizontal, side)
        .padding(.top, 8)
        .frame(width: W, height: H, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Wordmark(large: true)
            Spacer(minLength: 12)
            HStack(spacing: 0) {
                Button { model.nudgeTempo(-1) } label: {
                    Image(systemName: "minus").font(.system(size: 17, weight: .bold)).frame(width: 48, height: 48)
                }
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Slower")
                Text("\(Int(model.tempo)) BPM")
                    .font(GFont.pixel(26))
                    .foregroundStyle(Theme.lcd)
                    .frame(minWidth: 88)
                    .accessibilityLabel("Tempo \(Int(model.tempo)) beats per minute")
                Button { model.nudgeTempo(1) } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).frame(width: 48, height: 48)
                }
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Faster")
            }
            .foregroundStyle(Theme.rubber)
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cap))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.capLip).offset(y: 3))

            Button(action: model.shuffle) {
                Text("SHUFFLE").font(GFont.bold(15)).tracking(1.8).padding(.horizontal, 18).frame(height: 48)
            }
            .buttonStyle(OutlineButtonStyle())
            Button(action: model.clear) {
                Text("CLEAR").font(GFont.bold(15)).tracking(1.8).padding(.horizontal, 18).frame(height: 48)
            }
            .buttonStyle(OutlineButtonStyle())
            PlayButton(model: model, width: 124, height: 48, fontSize: 18)
        }
    }
}

struct MixerPanel: View {
    let model: GasworksModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIXER").font(GFont.bold(12)).tracking(2.4).foregroundStyle(Theme.printSoft)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { t in
                    let tr = model.tracks[t]
                    VStack(spacing: 8) {
                        Text("CH\(t + 1)")
                            .font(GFont.bold(13)).tracking(1.3)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.color(forPreset: tr.preset)))
                        VerticalFader(track: t, model: model)
                        Button { model.toggleMute(track: t) } label: {
                            Text("M").font(GFont.bold(15)).frame(width: 44, height: 32)
                        }
                        .buttonStyle(HardButtonStyle(fill: tr.muted ? Theme.red : Theme.cap,
                                                     lip: tr.muted ? Theme.redLip : Theme.capLip,
                                                     foreground: tr.muted ? .white : Theme.rubber, radius: 8))
                        .accessibilityLabel("Mute channel \(t + 1)")
                        .accessibilityAddTraits(tr.muted ? .isSelected : [])
                        Button { model.toggleSolo(track: t) } label: {
                            Text("S").font(GFont.bold(15)).frame(width: 44, height: 32)
                        }
                        .buttonStyle(HardButtonStyle(fill: tr.solo ? Theme.led : Theme.cap,
                                                     lip: tr.solo ? Theme.ledLip : Theme.capLip,
                                                     foreground: tr.solo ? Theme.cap : Theme.rubber, radius: 8))
                        .accessibilityLabel("Solo channel \(t + 1)")
                        .accessibilityAddTraits(tr.solo ? .isSelected : [])
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 3)
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(WellBackground(radius: 16))
    }
}

struct WideSequencer: View {
    let model: GasworksModel

    var body: some View {
        GeometryReader { geo in
            let rowGap: CGFloat = 8
            let headH: CGFloat = 20
            let rowH = max(30, min(76, (geo.size.height - 24 - headH - rowGap * 4) / 4))
            VStack(spacing: rowGap) {
                HStack(spacing: 10) {
                    Text("SEQUENCER")
                        .font(GFont.bold(12)).tracking(2.4)
                        .foregroundStyle(Theme.printSoft)
                        .frame(width: 160, alignment: .leading)
                    HStack(spacing: 5) {
                        ForEach(0..<16, id: \.self) { s in
                            Text(s % 4 == 0 ? "\(s / 4 + 1)" : "·")
                                .font(GFont.pixel(17))
                                .foregroundStyle(model.currentStep == s ? Theme.print : Theme.printFaint)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .frame(height: headH)
                ForEach(0..<4, id: \.self) { t in
                    HStack(spacing: 10) {
                        Menu {
                            SoundMenuItems(track: t, model: model)
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.color(forPreset: model.tracks[t].preset))
                                    .frame(width: 12, height: 12)
                                Text(Presets.all[model.tracks[t].preset].name.uppercased())
                                    .font(GFont.semi(15)).tracking(0.6)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(Theme.print)
                            .padding(.horizontal, 10)
                            .frame(width: 160, height: rowH)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.rubber))
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.rubberLip).offset(y: 2))
                        }
                        .accessibilityLabel("Channel \(t + 1) sound, \(Presets.all[model.tracks[t].preset].name)")
                        HStack(spacing: 5) {
                            ForEach(0..<16, id: \.self) { s in
                                StepCell(track: t, step: s, model: model, height: rowH)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background(WellBackground(radius: 16))
        }
    }
}
