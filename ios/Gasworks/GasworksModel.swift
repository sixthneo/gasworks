import SwiftUI
import Observation

struct Track: Codable, Equatable {
    var preset: Int
    var volume: Double
    var muted: Bool = false
    var solo: Bool = false
    var steps: [Bool]

    init(preset: Int, volume: Double, on: [Int]) {
        self.preset = preset
        self.volume = volume
        self.steps = (0..<16).map { on.contains($0) }
    }

    var stepMask: UInt16 {
        var m: UInt16 = 0
        for (i, on) in steps.enumerated() where on && i < 16 { m |= 1 << UInt16(i) }
        return m
    }
}

/// A knob on the panel: which setting it drives, its range, and how its value reads on screen.
struct KnobSpec: Identifiable {
    let id: String
    let label: String
    let keyPath: ReferenceWritableKeyPath<GasworksModel, Double>
    let range: ClosedRange<Double>
    let defaultValue: Double
    let format: (Double) -> String

    static let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    static let reverb = KnobSpec(id: "rev", label: "REVERB", keyPath: \.reverb, range: 0...1, defaultValue: 0.3, format: percent)
    static let delay = KnobSpec(id: "dly", label: "DELAY", keyPath: \.delay, range: 0...1, defaultValue: 0.15, format: percent)
    static let time = KnobSpec(id: "time", label: "TIME", keyPath: \.delayTime, range: 0...1, defaultValue: 0.32,
                               format: { "\(Int(((0.05 + $0 * 0.85) * 1000).rounded()))MS" })
    static let repeats = KnobSpec(id: "rpts", label: "REPEATS", keyPath: \.repeats, range: 0...1, defaultValue: 0.4, format: percent)
    static let pitch = KnobSpec(id: "pitch", label: "PITCH", keyPath: \.pitch, range: 0.5...2, defaultValue: 1,
                                format: { String(format: "x%.2f", $0) })
    static let drive = KnobSpec(id: "drive", label: "DRIVE", keyPath: \.drive, range: 0...1, defaultValue: 0.15, format: percent)
    static let tempo = KnobSpec(id: "tempo", label: "TEMPO", keyPath: \.tempo, range: 60...180, defaultValue: 100,
                                format: { "\(Int($0.rounded()))" })
    static let swing = KnobSpec(id: "swing", label: "SWING", keyPath: \.swing, range: 0...1, defaultValue: 0, format: percent)
    static let volume = KnobSpec(id: "vol", label: "VOLUME", keyPath: \.volume, range: 0...1, defaultValue: 0.8, format: percent)

    /// iPhone: tempo lives on a knob. iPad: tempo is in the top bar, so swing takes its place.
    static let phoneSet: [KnobSpec] = [reverb, delay, time, repeats, pitch, drive, tempo, volume]
    static let padSet: [KnobSpec] = [reverb, delay, time, repeats, pitch, drive, swing, volume]
}

private struct SavedState: Codable {
    var reverb, delay, delayTime, repeats, pitch, drive, tempo, swing, volume: Double
    var tracks: [Track]
}

@Observable
final class GasworksModel {
    // Panel
    var reverb = 0.3
    var delay = 0.15
    var delayTime = 0.32
    var repeats = 0.4
    var pitch = 1.0
    var drive = 0.15
    var tempo = 100.0
    var swing = 0.0
    var volume = 0.8

    // Sequencer and mixer
    var tracks: [Track] = GasworksModel.demoTracks
    var isPlaying = false
    var currentStep = -1
    var stepPage = 0

    // Display
    var selectedPad = 4
    var litPads: Set<Int> = []
    var hitTick = 0
    var lastHitPreset = 4
    var flashText: String?

    private let audio = AudioEngine()
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var flashWork: DispatchWorkItem?
    @ObservationIgnored private var unlightWork: [Int: DispatchWorkItem] = [:]

    static let demoTracks: [Track] = [
        Track(preset: 4, volume: 0.85, on: [0, 6, 8, 14]),   // Classic
        Track(preset: 1, volume: 0.7, on: [4, 12]),          // Duck
        Track(preset: 8, volume: 0.75, on: [0, 10]),         // Tuba
        Track(preset: 12, volume: 0.6, on: [7, 15]),         // Wet Slap
    ]

    private static let saveKey = "gasworks.state.v1"

    init() {
        load()
        pushAll()
        let timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: Knobs

    func value(_ spec: KnobSpec) -> Double { self[keyPath: spec.keyPath] }

    func set(_ spec: KnobSpec, _ newValue: Double, flash: Bool = true) {
        var v = min(spec.range.upperBound, max(spec.range.lowerBound, newValue))
        if spec.id == "tempo" { v = v.rounded() }
        guard v != self[keyPath: spec.keyPath] else { return }
        self[keyPath: spec.keyPath] = v
        pushAll()
        if flash { showFlash("\(spec.label) \(spec.format(v))") }
    }

    func nudgeTempo(_ delta: Double) { set(KnobSpec.tempo, tempo + delta) }

    // MARK: Pads

    func hit(_ pad: Int) {
        audio.start()
        audio.core.trigger(preset: pad, velocity: 1)
        selectedPad = pad
        lastHitPreset = pad
        hitTick &+= 1
        light(pad)
        flashText = nil
    }

    // MARK: Transport

    func togglePlay() {
        audio.start()
        isPlaying.toggle()
        if !isPlaying { currentStep = -1 }
        pushAll()
    }

    func clear() {
        for i in tracks.indices { tracks[i].steps = Array(repeating: false, count: 16) }
        pushAll()
    }

    func shuffle() {
        let density = [0.28, 0.18, 0.22, 0.1]
        let anchors = [4, 8, 9, 15, 10]
        for i in tracks.indices {
            if !(anchors.contains(tracks[i].preset) && Bool.random()) {
                tracks[i].preset = Int.random(in: 0..<Presets.all.count)
            }
            tracks[i].steps = (0..<16).map { s in
                Double.random(in: 0..<1) < density[i] + (i == 0 && s % 4 == 0 ? 0.5 : 0)
            }
        }
        pushAll()
    }

    // MARK: Sequencer + mixer

    func toggleStep(track: Int, step: Int) {
        tracks[track].steps[step].toggle()
        pushAll()
        if tracks[track].steps[step] && !isPlaying {
            audio.core.trigger(preset: tracks[track].preset, velocity: Float(tracks[track].volume))
            lastHitPreset = tracks[track].preset
            hitTick &+= 1
        }
    }

    func setPreset(track: Int, preset: Int) {
        tracks[track].preset = preset
        pushAll()
        audio.core.trigger(preset: preset, velocity: Float(tracks[track].volume))
        lastHitPreset = preset
        selectedPad = preset
        hitTick &+= 1
    }

    func setVolume(track: Int, _ v: Double) {
        let clamped = min(1, max(0, v))
        guard clamped != tracks[track].volume else { return }
        tracks[track].volume = clamped
        pushAll()
        showFlash("CH\(track + 1) \(Int((clamped * 100).rounded()))%")
    }

    func toggleMute(track: Int) {
        tracks[track].muted.toggle()
        pushAll()
    }

    func toggleSolo(track: Int) {
        tracks[track].solo.toggle()
        pushAll()
    }

    var anySolo: Bool { tracks.contains { $0.solo } }

    func isAudible(track: Int) -> Bool {
        anySolo ? tracks[track].solo : !tracks[track].muted
    }

    // MARK: Scope

    func scopeSamples(_ count: Int) -> [Float] { audio.core.scopeSamples(count: count) }

    // MARK: Plumbing

    private func pushAll() {
        audio.setEffects(reverb: reverb, delay: delay, time: delayTime, repeats: repeats)
        let p = SharedParams(playing: isPlaying, bpm: Float(tempo), swing: Float(swing),
                             pitch: Float(pitch), drive: Float(drive), volume: Float(volume))
        let t = tracks.map {
            TrackParams(preset: Int32($0.preset), volume: Float($0.volume), muted: $0.muted, solo: $0.solo, steps: $0.stepMask)
        }
        audio.core.update(params: p, tracks: t)
    }

    private func poll() {
        let (step, hits) = audio.core.poll()
        let shown = isPlaying ? step : -1
        if shown != currentStep { currentStep = shown }
        guard isPlaying, !hits.isEmpty else { return }
        for h in Set(hits) { light(h) }
        lastHitPreset = hits.last ?? lastHitPreset
        hitTick &+= 1
    }

    private func light(_ pad: Int) {
        litPads.insert(pad)
        unlightWork[pad]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.litPads.remove(pad) }
        unlightWork[pad] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.16, Presets.all[pad].dur * 0.7), execute: work)
    }

    private func showFlash(_ text: String) {
        flashText = text
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flashText = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func save() {
        let s = SavedState(reverb: reverb, delay: delay, delayTime: delayTime, repeats: repeats, pitch: pitch,
                           drive: drive, tempo: tempo, swing: swing, volume: volume, tracks: tracks)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.saveKey) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let s = try? JSONDecoder().decode(SavedState.self, from: data),
              s.tracks.count == 4, s.tracks.allSatisfy({ $0.steps.count == 16 }) else { return }
        reverb = s.reverb; delay = s.delay; delayTime = s.delayTime; repeats = s.repeats
        pitch = s.pitch; drive = s.drive; tempo = s.tempo; swing = s.swing; volume = s.volume
        tracks = s.tracks.map { var t = $0; t.preset = min(max(0, t.preset), Presets.all.count - 1); return t }
    }
}
