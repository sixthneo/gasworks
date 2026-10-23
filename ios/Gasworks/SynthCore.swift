import Foundation
import os

// MARK: - Real-time DSP
//
// Everything the audio thread touches lives in manually allocated memory and plain structs,
// so the render callback never allocates, never retains objects and never blocks.
// The UI thread hands over parameters and pad hits through a small lock that the audio
// thread only ever *tries* to take; if the UI is holding it, the audio thread keeps
// last buffer's values and catches up on the next one (a few milliseconds later).

struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    mutating func setLowpass(freq: Float, q: Float, sampleRate: Float) {
        let w0 = 2 * Float.pi * min(freq, sampleRate * 0.45) / sampleRate
        let cosw = cosf(w0), alpha = sinf(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = (1 - cosw) / 2 / a0
        b1 = (1 - cosw) / a0
        b2 = b0
        a1 = -2 * cosw / a0
        a2 = (1 - alpha) / a0
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    /// Band-pass with 0 dB peak gain (same shape as Web Audio's "bandpass").
    mutating func setBandpass(freq: Float, q: Float, sampleRate: Float) {
        let w0 = 2 * Float.pi * min(freq, sampleRate * 0.45) / sampleRate
        let cosw = cosf(w0), alpha = sinf(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2 * cosw / a0
        a2 = (1 - alpha) / a0
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

struct XorShift {
    var state: UInt32 = 0x9E37_79B9
    /// Uniform 0…1
    @inline(__always) mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(state) * (1.0 / 4_294_967_296.0)
    }
    @inline(__always) mutating func bipolar() -> Float { next() * 2 - 1 }
}

/// Plain-data copy of a FartPreset that the audio thread can read.
struct PresetDSP {
    var f0: Float = 0, f1: Float = 0, dur: Float = 0.5
    var flutter: Float = 0, depth: Float = 0
    var noise: Float = 0, noiseFreq: Float = 600
    var tone: Float = 1, lowpass: Float = 1000, wobble: Float = 0, amp: Float = 1
    var squeak: Bool = false
    var bubbles: Int32 = 0
    var partCount: Int32 = 1
}

struct SharedParams {
    var playing = false
    var bpm: Float = 100
    var swing: Float = 0
    var pitch: Float = 1
    var drive: Float = 0.15
    var volume: Float = 0.8
}

struct TrackParams {
    var preset: Int32 = 0
    var volume: Float = 0.8
    var muted = false
    var solo = false
    /// Bit n set = step n is on.
    var steps: UInt16 = 0
}

struct PadTrigger {
    var preset: Int32
    var velocity: Float
}

struct Voice {
    var active = false
    var channel: Int32 = -1
    var delay: Int32 = 0
    var t: Float = 0
    var dur: Float = 0, hold: Float = 0, end: Float = 0
    var amp: Float = 0
    var fStart: Float = 0, logRatio: Float = 0
    var phase: Float = 0, sqPhase: Float = 0
    var toneGain: Float = 0, squeakGain: Float = 0, noiseGain: Float = 0
    var wobble: Float = 0, detune: Float = 0, detuneTarget: Float = 0, wobbleTimer: Float = 0
    var flutter: Float = 0, depth: Float = 0, flPhase: Float = 0, flRate: Float = 0, low: Float = 1, am: Float = 1
    var bp = Biquad()
    var lp = Biquad()

    @inline(__always)
    mutating func process(dt: Float, kDetune: Float, kAm: Float, rng: inout XorShift) -> Float {
        if delay > 0 { delay -= 1; return 0 }

        // Pitch: exponential glide from f0 to f1 plus a smoothed random wobble.
        let x = min(t / dur, 1)
        let glide = fStart * expf(logRatio * x)
        wobbleTimer -= dt
        if wobbleTimer <= 0 {
            wobbleTimer += 0.035
            detuneTarget = rng.bipolar() * wobble * 120
        }
        detune += (detuneTarget - detune) * kDetune
        let f = glide * exp2f(detune / 1200)

        var src: Float = 0
        if toneGain > 0 {
            phase += f * dt
            if phase >= 1 { phase -= floorf(phase) }
            src += (2 * phase - 1) * toneGain
            if squeakGain > 0 {
                sqPhase += 2 * f * dt
                if sqPhase >= 1 { sqPhase -= floorf(sqPhase) }
                src += (4 * abs(sqPhase - 0.5) - 1) * squeakGain
            }
        }
        if noiseGain > 0 {
            src += bp.process(rng.bipolar()) * noiseGain
        }
        let y = lp.process(src)

        // Flutter: an irregular square-ish chop of the amplitude. This is the "brrrt".
        if flutter > 0 {
            flPhase += flRate * dt
            if flPhase >= 1 {
                flPhase -= 1
                flRate = flutter * (0.85 + 0.3 * rng.next())
                low = 1 - depth * (0.55 + 0.45 * rng.next())
            }
            let target: Float = flPhase < 0.5 ? 1 : low
            am += (target - am) * kAm
        }

        // Envelope: 12 ms attack, hold for 75% of the length, then an exponential tail.
        let env: Float
        if t < 0.012 {
            env = amp * t / 0.012
        } else if t < hold {
            env = amp
        } else {
            env = amp * expf(-7.6 * (t - hold) / max(0.001, end - hold))
        }

        t += dt
        if t > end + 0.04 { active = false }
        return y * am * env
    }
}

struct Bubble {
    var active = false
    var channel: Int32 = -1
    var delay: Int32 = 0
    var t: Float = 0
    var f: Float = 0
    var phase: Float = 0
    var amp: Float = 0

    @inline(__always)
    mutating func process(dt: Float) -> Float {
        if delay > 0 { delay -= 1; return 0 }
        let k = min(t / 0.05, 1)
        let freq = f * expf(0.5878 * k) // rises to 1.8× over 50 ms
        phase += freq * dt
        if phase >= 1 { phase -= 1 }
        let s = sinf(2 * Float.pi * phase)
        let env: Float = t < 0.004 ? amp * t / 0.004 : amp * expf(-6.9 * (t - 0.004) / 0.056)
        t += dt
        if t > 0.07 { active = false }
        return s * env
    }
}

struct SeqState {
    var running = false
    var step: Int32 = 0
    var samplesLeft: Double = 0
}

/// A bundle of raw pointers. Copied by value into the render closure, so the audio thread
/// never touches a Swift object.
struct SynthKernel {
    static let maxVoices = 48
    static let maxBubbles = 96
    static let trackCount = 4
    static let stepCount = 16
    static let queueSize = 32
    static let hitRingSize = 32
    static let scopeSize = 1024

    let sampleRate: Float
    let presetCount: Int
    let lock: UnsafeMutablePointer<os_unfair_lock>

    // Written by the UI under the lock
    let sharedParams: UnsafeMutablePointer<SharedParams>
    let sharedTracks: UnsafeMutablePointer<TrackParams>
    let queue: UnsafeMutablePointer<PadTrigger>
    let queueCount: UnsafeMutablePointer<Int>

    // Written by the audio thread under the lock, read by the UI
    let outStep: UnsafeMutablePointer<Int32>
    let outHits: UnsafeMutablePointer<Int32>
    let outHitTotal: UnsafeMutablePointer<Int>

    // Audio-thread only
    let params: UnsafeMutablePointer<SharedParams>
    let tracks: UnsafeMutablePointer<TrackParams>
    let chanGain: UnsafeMutablePointer<Float>
    let presets: UnsafeMutablePointer<PresetDSP>
    let parts: UnsafeMutablePointer<Float>
    let voices: UnsafeMutablePointer<Voice>
    let bubbles: UnsafeMutablePointer<Bubble>
    let rng: UnsafeMutablePointer<XorShift>
    let seq: UnsafeMutablePointer<SeqState>
    let pendStep: UnsafeMutablePointer<Int32>
    let pendHits: UnsafeMutablePointer<Int32>
    let pendHitCount: UnsafeMutablePointer<Int>

    // Read by the UI without locking (a torn read only means a slightly glitchy scope frame)
    let scope: UnsafeMutablePointer<Float>
    let scopeIndex: UnsafeMutablePointer<Int>

    init(sampleRate: Double, presetList: [FartPreset]) {
        self.sampleRate = Float(sampleRate)
        presetCount = presetList.count
        lock = .allocate(capacity: 1); lock.initialize(to: os_unfair_lock())
        sharedParams = .allocate(capacity: 1); sharedParams.initialize(to: SharedParams())
        sharedTracks = .allocate(capacity: Self.trackCount); sharedTracks.initialize(repeating: TrackParams(), count: Self.trackCount)
        queue = .allocate(capacity: Self.queueSize); queue.initialize(repeating: PadTrigger(preset: 0, velocity: 0), count: Self.queueSize)
        queueCount = .allocate(capacity: 1); queueCount.initialize(to: 0)
        outStep = .allocate(capacity: 1); outStep.initialize(to: -1)
        outHits = .allocate(capacity: Self.hitRingSize); outHits.initialize(repeating: 0, count: Self.hitRingSize)
        outHitTotal = .allocate(capacity: 1); outHitTotal.initialize(to: 0)
        params = .allocate(capacity: 1); params.initialize(to: SharedParams())
        tracks = .allocate(capacity: Self.trackCount); tracks.initialize(repeating: TrackParams(), count: Self.trackCount)
        chanGain = .allocate(capacity: Self.trackCount); chanGain.initialize(repeating: 1, count: Self.trackCount)
        presets = .allocate(capacity: presetList.count); presets.initialize(repeating: PresetDSP(), count: presetList.count)
        parts = .allocate(capacity: presetList.count * Presets.maxParts); parts.initialize(repeating: 0, count: presetList.count * Presets.maxParts)
        voices = .allocate(capacity: Self.maxVoices); voices.initialize(repeating: Voice(), count: Self.maxVoices)
        bubbles = .allocate(capacity: Self.maxBubbles); bubbles.initialize(repeating: Bubble(), count: Self.maxBubbles)
        rng = .allocate(capacity: 1); rng.initialize(to: XorShift())
        seq = .allocate(capacity: 1); seq.initialize(to: SeqState())
        pendStep = .allocate(capacity: 1); pendStep.initialize(to: -1)
        pendHits = .allocate(capacity: Self.hitRingSize); pendHits.initialize(repeating: 0, count: Self.hitRingSize)
        pendHitCount = .allocate(capacity: 1); pendHitCount.initialize(to: 0)
        scope = .allocate(capacity: Self.scopeSize); scope.initialize(repeating: 0, count: Self.scopeSize)
        scopeIndex = .allocate(capacity: 1); scopeIndex.initialize(to: 0)

        for (i, p) in presetList.enumerated() {
            presets[i] = PresetDSP(
                f0: Float(p.f0), f1: Float(p.f1), dur: Float(p.dur),
                flutter: Float(p.flutter), depth: Float(p.depth),
                noise: Float(p.noise), noiseFreq: Float(p.noiseFreq),
                tone: Float(p.tone), lowpass: Float(p.lowpass), wobble: Float(p.wobble), amp: Float(p.amp),
                squeak: p.squeak, bubbles: Int32(p.bubbles),
                partCount: Int32(min(p.parts.count, Presets.maxParts)))
            for (k, offset) in p.parts.prefix(Presets.maxParts).enumerated() {
                parts[i * Presets.maxParts + k] = Float(offset)
            }
        }
    }

    func deallocate() {
        lock.deallocate()
        sharedParams.deallocate(); sharedTracks.deallocate(); queue.deallocate(); queueCount.deallocate()
        outStep.deallocate(); outHits.deallocate(); outHitTotal.deallocate()
        params.deallocate(); tracks.deallocate(); chanGain.deallocate(); presets.deallocate(); parts.deallocate()
        voices.deallocate(); bubbles.deallocate(); rng.deallocate(); seq.deallocate()
        pendStep.deallocate(); pendHits.deallocate(); pendHitCount.deallocate()
        scope.deallocate(); scopeIndex.deallocate()
    }

    // MARK: Audio thread

    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        // 1. Pull in the UI's latest settings and any pad hits.
        if os_unfair_lock_trylock(lock) {
            params.pointee = sharedParams.pointee
            for i in 0..<Self.trackCount { tracks[i] = sharedTracks[i] }
            let n = queueCount.pointee
            for i in 0..<n { startSound(preset: Int(queue[i].preset), channel: -1, velocity: queue[i].velocity) }
            queueCount.pointee = 0
            os_unfair_lock_unlock(lock)
        }

        let p = params.pointee
        var anySolo = false
        for i in 0..<Self.trackCount where tracks[i].solo { anySolo = true }
        for i in 0..<Self.trackCount {
            let t = tracks[i]
            let audible = anySolo ? t.solo : !t.muted
            chanGain[i] = audible ? t.volume : 0
        }

        if p.playing && !seq.pointee.running {
            seq.pointee = SeqState(running: true, step: 0, samplesLeft: 0)
        } else if !p.playing && seq.pointee.running {
            seq.pointee.running = false
            pendStep.pointee = -1
        }

        let dt = 1 / sampleRate
        let kDetune = 1 - expf(-dt / 0.01)
        let kAm = 1 - expf(-dt / 0.0025)
        let k = 1 + p.drive * 14
        let norm = 1 / tanhf(k)
        let outGain = p.volume * (1 - p.drive * 0.35)
        let baseStep = Double(sampleRate) * 60 / Double(max(30, p.bpm)) / 4
        let swing = Double(p.swing) * 0.33

        for i in 0..<frames {
            // 2. Sequencer, sample-accurate.
            if seq.pointee.running {
                if seq.pointee.samplesLeft <= 0 {
                    let step = Int(seq.pointee.step)
                    fireStep(step, anySolo: anySolo)
                    pendStep.pointee = Int32(step)
                    seq.pointee.samplesLeft += step % 2 == 0 ? baseStep * (1 + swing) : baseStep * (1 - swing)
                    seq.pointee.step = Int32((step + 1) % Self.stepCount)
                }
                seq.pointee.samplesLeft -= 1
            }

            // 3. Voices.
            var mix: Float = 0
            for v in 0..<Self.maxVoices {
                let vp = voices + v
                if vp.pointee.active {
                    let s = vp.pointee.process(dt: dt, kDetune: kDetune, kAm: kAm, rng: &rng.pointee)
                    let ch = Int(vp.pointee.channel)
                    mix += ch < 0 ? s : s * chanGain[ch]
                }
            }
            for b in 0..<Self.maxBubbles {
                let bp = bubbles + b
                if bp.pointee.active {
                    let s = bp.pointee.process(dt: dt)
                    let ch = Int(bp.pointee.channel)
                    mix += ch < 0 ? s : s * chanGain[ch]
                }
            }

            // 4. Drive + master.
            var out = tanhf(mix * k) * norm * outGain
            out = max(-1, min(1, out))
            left[i] = out
            if let right { right[i] = out }

            let si = scopeIndex.pointee
            scope[si] = out
            scopeIndex.pointee = (si + 1) & (Self.scopeSize - 1)
        }

        // 5. Publish the playhead and sequencer hits for the UI.
        if os_unfair_lock_trylock(lock) {
            outStep.pointee = pendStep.pointee
            let n = pendHitCount.pointee
            for h in 0..<n {
                outHits[(outHitTotal.pointee + h) % Self.hitRingSize] = pendHits[h]
            }
            outHitTotal.pointee += n
            pendHitCount.pointee = 0
            os_unfair_lock_unlock(lock)
        }
    }

    private func fireStep(_ step: Int, anySolo: Bool) {
        let bit = UInt16(1) << UInt16(step)
        for t in 0..<Self.trackCount {
            let tr = tracks[t]
            guard tr.steps & bit != 0 else { continue }
            let audible = anySolo ? tr.solo : !tr.muted
            guard audible else { continue }
            startSound(preset: Int(tr.preset), channel: Int32(t), velocity: 0.95)
            if pendHitCount.pointee < Self.hitRingSize {
                pendHits[pendHitCount.pointee] = tr.preset
                pendHitCount.pointee += 1
            }
        }
    }

    private func startSound(preset: Int, channel: Int32, velocity: Float) {
        guard preset >= 0 && preset < presetCount else { return }
        let pr = presets[preset]
        let pitch = params.pointee.pitch
        let rootPitch = sqrtf(pitch)

        if (pr.tone > 0 && pr.f0 > 0) || pr.noise > 0 {
            for k in 0..<Int(pr.partCount) {
                let offset = parts[preset * Presets.maxParts + k]
                startVoice(pr, channel: channel, velocity: velocity, pitch: pitch, rootPitch: rootPitch,
                           delay: Int32(offset * sampleRate))
            }
        }
        if pr.bubbles > 0 {
            for _ in 0..<Int(pr.bubbles) {
                let slot = freeBubble()
                var b = Bubble()
                b.active = true
                b.channel = channel
                b.delay = Int32(rng.pointee.next() * pr.dur * sampleRate)
                b.f = (250 + rng.pointee.next() * 450) * pitch
                b.amp = 0.35 * velocity
                bubbles[slot] = b
            }
        }
    }

    private func startVoice(_ pr: PresetDSP, channel: Int32, velocity: Float, pitch: Float, rootPitch: Float, delay: Int32) {
        let slot = freeVoice()
        var v = Voice()
        v.active = true
        v.channel = channel
        v.delay = delay
        v.dur = pr.dur
        v.hold = max(0.02, pr.dur * 0.75)
        v.end = pr.dur + 0.06
        v.amp = pr.amp * velocity * 0.9
        let fS = pr.f0 * pitch, fE = pr.f1 * pitch
        v.fStart = fS
        v.logRatio = (fS > 0 && fE > 0) ? logf(fE / fS) : 0
        v.toneGain = pr.f0 > 0 ? pr.tone * 0.6 : 0
        v.squeakGain = (pr.squeak && pr.f0 > 0) ? 0.25 : 0
        v.noiseGain = pr.noise
        v.wobble = pr.wobble
        v.flutter = pr.flutter
        v.depth = pr.depth
        v.flRate = pr.flutter * (0.85 + 0.3 * rng.pointee.next())
        v.low = 1 - pr.depth * (0.55 + 0.45 * rng.pointee.next())
        v.phase = rng.pointee.next()
        v.lp.setLowpass(freq: min(8000, pr.lowpass * rootPitch), q: 3, sampleRate: sampleRate)
        v.bp.setBandpass(freq: pr.noiseFreq * rootPitch, q: 0.9, sampleRate: sampleRate)
        voices[slot] = v
    }

    private func freeVoice() -> Int {
        var oldest = 0
        var oldestT: Float = -1
        for i in 0..<Self.maxVoices {
            if !voices[i].active { return i }
            if voices[i].t > oldestT { oldestT = voices[i].t; oldest = i }
        }
        return oldest
    }

    private func freeBubble() -> Int {
        var oldest = 0
        var oldestT: Float = -1
        for i in 0..<Self.maxBubbles {
            if !bubbles[i].active { return i }
            if bubbles[i].t > oldestT { oldestT = bubbles[i].t; oldest = i }
        }
        return oldest
    }
}

// MARK: - UI-side handle

/// Owned by the main thread. Talks to the kernel through the lock.
final class SynthCore {
    let kernel: SynthKernel
    private var seenHits = 0

    init(sampleRate: Double) {
        kernel = SynthKernel(sampleRate: sampleRate, presetList: Presets.all)
    }

    deinit { kernel.deallocate() }

    func update(params: SharedParams, tracks: [TrackParams]) {
        os_unfair_lock_lock(kernel.lock)
        kernel.sharedParams.pointee = params
        for i in 0..<min(tracks.count, SynthKernel.trackCount) { kernel.sharedTracks[i] = tracks[i] }
        os_unfair_lock_unlock(kernel.lock)
    }

    func trigger(preset: Int, velocity: Float) {
        os_unfair_lock_lock(kernel.lock)
        let n = kernel.queueCount.pointee
        if n < SynthKernel.queueSize {
            kernel.queue[n] = PadTrigger(preset: Int32(preset), velocity: velocity)
            kernel.queueCount.pointee = n + 1
        }
        os_unfair_lock_unlock(kernel.lock)
    }

    /// The playhead step (-1 when stopped) and the presets the sequencer fired since the last poll.
    func poll() -> (step: Int, hits: [Int]) {
        os_unfair_lock_lock(kernel.lock)
        let step = Int(kernel.outStep.pointee)
        let total = kernel.outHitTotal.pointee
        var hits: [Int] = []
        let start = max(seenHits, total - SynthKernel.hitRingSize)
        if total > start {
            for h in start..<total { hits.append(Int(kernel.outHits[h % SynthKernel.hitRingSize])) }
        }
        seenHits = total
        os_unfair_lock_unlock(kernel.lock)
        return (step, hits)
    }

    /// The most recent `count` output samples, oldest first.
    func scopeSamples(count: Int) -> [Float] {
        let size = SynthKernel.scopeSize
        let end = kernel.scopeIndex.pointee
        let n = min(count, size)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = kernel.scope[(end - n + i + size) & (size - 1)]
        }
        return out
    }
}
