import Foundation

func makeWav(pcm16Mono16k pcm: Data, sampleRate: Int, channels: Int) -> Data {
    let bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = Int32(pcm.count)
    let riffSize = Int32(36) + dataSize

    var out = Data()
    out.append("RIFF".data(using: .ascii)!)
    out.append(contentsOf: withUnsafeBytes(of: riffSize.littleEndian, Array.init))
    out.append("WAVE".data(using: .ascii)!)
    out.append("fmt ".data(using: .ascii)!)

    let fmtChunkSize: Int32 = 16
    let audioFormat: Int16 = 1
    let numChannels: Int16 = Int16(channels)
    let sr: Int32 = Int32(sampleRate)
    let br: Int32 = Int32(byteRate)
    let ba: Int16 = Int16(blockAlign)
    let bps: Int16 = Int16(bitsPerSample)

    out.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: sr.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: br.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: ba.littleEndian, Array.init))
    out.append(contentsOf: withUnsafeBytes(of: bps.littleEndian, Array.init))

    out.append("data".data(using: .ascii)!)
    out.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
    out.append(pcm)
    return out
}
