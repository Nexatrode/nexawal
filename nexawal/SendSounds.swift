import AVFoundation
import Foundation

/// Optional, short send-result tones. Ambient audio respects the iPhone Ring/Silent switch.
@MainActor
enum SendSounds {
    static let setting = MoneroConfig.userDefaultsSendSoundsKey

    private static var player: AVAudioPlayer?

    static func success() { play(success: true) }
    static func failure() { play(success: false) }

    private static func play(success: Bool) {
        guard UserDefaults.standard.object(forKey: setting) as? Bool
                ?? MoneroConfig.defaultSendSoundsEnabled else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            player?.stop()
            let nextPlayer = try AVAudioPlayer(data: makeWave(success: success))
            nextPlayer.volume = 0.22
            player = nextPlayer
            nextPlayer.play()
        } catch {
            // Audio is a best-effort cue; it must never affect wallet/send state.
        }
    }

    private static func makeWave(success: Bool) -> Data {
        let sampleRate: UInt32 = 22_050
        let notes: [(frequency: Double, duration: Double)] = success
            ? [(659.25, 0.065), (880.0, 0.095)]
            : [(330.0, 0.15)]
        var samples: [Int16] = []

        for note in notes {
            let count = Int(Double(sampleRate) * note.duration)
            for index in 0..<count {
                let position = Double(index) / Double(sampleRate)
                let attack = min(1.0, Double(index) / 180.0)
                let release = min(1.0, Double(count - index) / 500.0)
                let envelope = min(attack, release)
                let value = sin(2.0 * .pi * note.frequency * position) * envelope * 0.22
                samples.append(Int16(value * Double(Int16.max)))
            }
        }

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendLE(UInt32(36 + samples.count * 2), to: &data)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        appendLE(UInt32(16), to: &data)
        appendLE(UInt16(1), to: &data) // PCM
        appendLE(UInt16(1), to: &data) // mono
        appendLE(sampleRate, to: &data)
        appendLE(sampleRate * 2, to: &data) // byte rate
        appendLE(UInt16(2), to: &data) // block alignment
        appendLE(UInt16(16), to: &data) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendLE(UInt32(samples.count * 2), to: &data)
        for sample in samples { appendLE(UInt16(bitPattern: sample), to: &data) }
        return data
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
