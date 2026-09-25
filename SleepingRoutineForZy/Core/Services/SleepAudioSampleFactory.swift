import Foundation

/// Builds short looping WAV samples for app-owned bedtime audio.
/// No binary assets required — keeps the repo free of large media files.
enum SleepAudioSampleFactory {
    static func makeWAV(for sound: QuietSound) -> Data {
        switch sound {
        case .softTone:
            return makeSoftToneWAV(frequency: 174, amplitude: 0.04)
        case .deepHum:
            return makeSoftToneWAV(frequency: 110, amplitude: 0.035)
        case .whiteNoise:
            return makeNoiseWAV(filtered: false, amplitude: 0.025)
        case .rain:
            return makeNoiseWAV(filtered: true, amplitude: 0.03)
        }
    }

    static func makeSoftToneWAV(
        durationSeconds: Double = 2.0,
        sampleRate: Double = 22_050,
        frequency: Double = 174.0,
        amplitude: Float = 0.04
    ) -> Data {
        let frameCount = Int(durationSeconds * sampleRate)
        var data = Data()
        data.reserveCapacity(44 + frameCount * 2)

        func appendUInt32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let byteRate = UInt32(sampleRate * 2)
        let dataSize = UInt32(frameCount * 2)

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(byteRate)
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize)

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let fadeFrames = Int(sampleRate * 0.15)
            let fadeIn = frame < fadeFrames ? Float(frame) / Float(fadeFrames) : 1
            let fadeOut = frame > frameCount - fadeFrames
                ? Float(frameCount - frame) / Float(fadeFrames)
                : 1
            let sample = sin(2 * Double.pi * frequency * t) * Double(amplitude * fadeIn * fadeOut)
            let intSample = Int16(max(-1, min(1, sample)) * Double(Int16.max))
            var le = intSample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        return data
    }

    static func makeNoiseWAV(
        durationSeconds: Double = 2.0,
        sampleRate: Double = 22_050,
        filtered: Bool,
        amplitude: Float
    ) -> Data {
        let frameCount = Int(durationSeconds * sampleRate)
        var data = Data()
        data.reserveCapacity(44 + frameCount * 2)

        func appendUInt32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        let byteRate = UInt32(sampleRate * 2)
        let dataSize = UInt32(frameCount * 2)

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(byteRate)
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize)

        var prev: Float = 0
        var seed: UInt64 = 42
        for frame in 0..<frameCount {
            seed = seed &* 6364136223846793005 &+ 1
            let unit = Float(seed >> 33) / Float(UInt32.max)
            var n = unit * 2 - 1
            if filtered {
                n = prev * 0.85 + n * 0.15
                prev = n
            }
            let fadeFrames = Int(sampleRate * 0.15)
            let fadeIn = frame < fadeFrames ? Float(frame) / Float(fadeFrames) : 1
            let fadeOut = frame > frameCount - fadeFrames
                ? Float(frameCount - frame) / Float(fadeFrames)
                : 1
            let sample = Double(n * amplitude * fadeIn * fadeOut)
            let intSample = Int16(max(-1, min(1, sample)) * Double(Int16.max))
            var le = intSample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        return data
    }

    static var riffHeaderIsValid: (Data) -> Bool = { data in
        guard data.count > 12 else { return false }
        return String(data: data.prefix(4), encoding: .ascii) == "RIFF"
    }
}
