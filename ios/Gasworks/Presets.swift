import Foundation

/// The four sound families. They decide pad order and the colour of a pad's LED and of a sequencer channel.
enum SoundFamily: Int, CaseIterable, Codable {
    case short, classic, big, wet

    var label: String {
        switch self {
        case .short: return "SHORT"
        case .classic: return "CLASSIC"
        case .big: return "BIG"
        case .wet: return "WET · FX"
        }
    }
}

/// One fart voice recipe. All the numbers mirror the web version of Gasworks G-1.
struct FartPreset: Identifiable, Hashable {
    let id: Int
    let name: String
    let family: SoundFamily
    /// Start and end pitch of the sawtooth, in Hz (glides exponentially).
    var f0: Double = 0
    var f1: Double = 0
    /// Length of one part, in seconds.
    var dur: Double
    /// Flutter (amplitude chop) rate in Hz and how deep it chops, 0–1.
    var flutter: Double = 0
    var depth: Double = 0
    /// Breath noise level and the centre of its band-pass filter.
    var noise: Double = 0
    var noiseFreq: Double = 600
    /// Level of the sawtooth body. 0 removes it entirely.
    var tone: Double = 1
    /// Low-pass cutoff in Hz.
    var lowpass: Double = 1000
    /// Random pitch wobble, roughly in semitones.
    var wobble: Double = 0
    /// Adds a triangle wave an octave up.
    var squeak: Bool = false
    /// Number of bubble blips scattered across the sound.
    var bubbles: Int = 0
    var amp: Double = 1
    /// Start offsets, in seconds, when one hit plays several parts (Machine Gun, Duck, Stutter).
    var parts: [Double] = [0]
}

enum Presets {
    /// Ordered by family so the 4×4 pad grid reads Short / Classic / Big / Wet & FX, row by row.
    static let all: [FartPreset] = [
        FartPreset(id: 0, name: "Tiny Toot", family: .short, f0: 205, f1: 190, dur: 0.12, flutter: 40, depth: 0.6, noise: 0.05, lowpass: 1800, wobble: 0.05),
        FartPreset(id: 1, name: "Duck", family: .short, f0: 270, f1: 205, dur: 0.22, flutter: 36, depth: 0.6, noise: 0.1, lowpass: 2200, wobble: 0.1, parts: [0, 0.3]),
        FartPreset(id: 2, name: "Stutter", family: .short, f0: 135, f1: 118, dur: 0.16, flutter: 30, depth: 0.85, noise: 0.2, lowpass: 1200, wobble: 0.15, parts: [0, 0.22, 0.3, 0.52]),
        FartPreset(id: 3, name: "Machine Gun", family: .short, f0: 120, f1: 105, dur: 0.09, flutter: 34, depth: 0.8, noise: 0.2, lowpass: 1200, wobble: 0.1, parts: [0, 0.13, 0.26, 0.39, 0.52, 0.65]),

        FartPreset(id: 4, name: "Classic", family: .classic, f0: 110, f1: 80, dur: 0.7, flutter: 28, depth: 0.8, noise: 0.15, lowpass: 900, wobble: 0.15),
        FartPreset(id: 5, name: "Squeaker", family: .classic, f0: 330, f1: 430, dur: 0.55, flutter: 46, depth: 0.55, noise: 0.05, lowpass: 2600, wobble: 0.3, squeak: true),
        FartPreset(id: 6, name: "Whoopee", family: .classic, f0: 185, f1: 88, dur: 1.3, flutter: 31, depth: 0.7, noise: 0.3, lowpass: 1500, wobble: 0.5),
        FartPreset(id: 7, name: "Balloon", family: .classic, f0: 420, f1: 260, dur: 1.0, flutter: 62, depth: 0.5, noise: 0.05, lowpass: 3200, wobble: 0.35, squeak: true),

        FartPreset(id: 8, name: "Tuba", family: .big, f0: 55, f1: 46, dur: 1.2, flutter: 17, depth: 0.9, noise: 0.1, lowpass: 480, wobble: 0.1),
        FartPreset(id: 9, name: "Rumble", family: .big, f0: 42, f1: 36, dur: 1.6, flutter: 11, depth: 1.0, noise: 0.15, lowpass: 320, wobble: 0.2, amp: 1.2),
        FartPreset(id: 10, name: "Long Haul", family: .big, f0: 105, f1: 68, dur: 2.4, flutter: 24, depth: 0.75, noise: 0.2, lowpass: 1000, wobble: 0.45),
        FartPreset(id: 11, name: "Silent Deadly", family: .big, f0: 80, f1: 70, dur: 1.5, flutter: 14, depth: 0.35, noise: 0.9, noiseFreq: 1400, tone: 0.12, lowpass: 1600, wobble: 0.1, amp: 0.6),

        FartPreset(id: 12, name: "Wet Slap", family: .wet, f0: 90, f1: 62, dur: 0.45, flutter: 22, depth: 0.9, noise: 0.75, noiseFreq: 500, lowpass: 1100, wobble: 0.25, bubbles: 6),
        FartPreset(id: 13, name: "Bathtub", family: .wet, dur: 1.3, tone: 0, lowpass: 1500, bubbles: 16),
        FartPreset(id: 14, name: "Riser", family: .wet, f0: 70, f1: 230, dur: 0.9, flutter: 26, depth: 0.75, noise: 0.1, lowpass: 1800, wobble: 0.15),
        FartPreset(id: 15, name: "Faller", family: .wet, f0: 250, f1: 58, dur: 0.9, flutter: 30, depth: 0.75, noise: 0.1, lowpass: 1800, wobble: 0.15),
    ]

    static let maxParts = 6
}
