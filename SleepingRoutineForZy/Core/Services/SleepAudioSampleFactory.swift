import Foundation

/// Builds a short looping WAV of a soft low tone for app-owned bedtime audio.
/// No binary asset required — keeps the repo free of large media files.
enum SleepAudioSampleFactory {
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

        let byteRate = UInt32(sampleRate * 2) // mono 16-bit
        let dataSize = UInt32(frameCount * 2)

        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16) // PCM chunk size
        appendUInt16(1) // PCM format
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(byteRate)
        appendUInt16(2) // block align
        appendUInt16(16) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(dataSize)

        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            // Soft envelope so loop boundaries are gentle.
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

    static var riffHeaderIsValid: (Data) -> Bool = { data in
        guard data.count > 12 else { return false }
        return String(data: data.prefix(4), encoding: .ascii) == "RIFF"
            && String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE"
    }
}
