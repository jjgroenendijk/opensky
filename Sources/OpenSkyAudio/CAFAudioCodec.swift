// Writes and reads decoded audio as Core Audio Format files, encoded by the
// codecs built into macOS (AudioToolbox). PCM is exact, ALAC stores 16-bit
// samples losslessly, and AAC is lossy.

import AudioToolbox
import Foundation

nonisolated public enum CAFAudioFormat: String, CaseIterable, Codable, Sendable {
    case pcmFloat32
    case alac
    case aac
}

nonisolated public enum CAFAudioCodecError: Error, Equatable, Sendable {
    case status(operation: String, code: Int32)
    case emptyAudio
}

nonisolated public enum CAFAudioCodec {
    public static func write(_ audio: DecodedAudio, to url: URL, format: CAFAudioFormat) throws {
        guard audio.frameCount > 0, audio.channelCount > 0 else {
            throw CAFAudioCodecError.emptyAudio
        }
        var fileFormat = fileDescription(format, audio: audio)
        var file: ExtAudioFileRef?
        try check("create", ExtAudioFileCreateWithURL(
            url as CFURL, kAudioFileCAFType, &fileFormat, nil,
            AudioFileFlags.eraseFile.rawValue, &file
        ))
        guard let file else { throw CAFAudioCodecError.status(operation: "create", code: -1) }
        defer { ExtAudioFileDispose(file) }
        try setClientFormat(file, sampleRate: audio.sampleRate, channels: audio.channelCount)
        var samples = audio.samples
        try samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(audio.channelCount),
                    mDataByteSize: UInt32(raw.count),
                    mData: raw.baseAddress
                )
            )
            try check("write", ExtAudioFileWrite(file, UInt32(audio.frameCount), &list))
        }
    }

    /// Decodes the whole file to interleaved Float samples at its own rate.
    public static func read(_ url: URL) throws -> DecodedAudio {
        var file: ExtAudioFileRef?
        try check("open", ExtAudioFileOpenURL(url as CFURL, &file))
        guard let file else { throw CAFAudioCodecError.status(operation: "open", code: -1) }
        defer { ExtAudioFileDispose(file) }
        return try readAll(file)
    }

    /// Decodes CAF bytes held in memory, such as a mapped cache entry.
    public static func read(_ data: Data) throws -> DecodedAudio {
        let source = MemoryAudioSource(data: data)
        let context = Unmanaged.passUnretained(source).toOpaque()
        var audioFile: AudioFileID?
        return try withExtendedLifetime(source) {
            try check("open", AudioFileOpenWithCallbacks(
                context, MemoryAudioSource.read, nil, MemoryAudioSource.size, nil,
                kAudioFileCAFType, &audioFile
            ))
            guard let audioFile
            else { throw CAFAudioCodecError.status(operation: "open", code: -1) }
            defer { AudioFileClose(audioFile) }
            var file: ExtAudioFileRef?
            try check("wrap", ExtAudioFileWrapAudioFileID(audioFile, false, &file))
            guard let file else { throw CAFAudioCodecError.status(operation: "wrap", code: -1) }
            defer { ExtAudioFileDispose(file) }
            return try readAll(file)
        }
    }

    private static func readAll(_ file: ExtAudioFileRef) throws -> DecodedAudio {
        var source = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("format", ExtAudioFileGetProperty(
            file, kExtAudioFileProperty_FileDataFormat, &size, &source
        ))
        var frames: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        try check("length", ExtAudioFileGetProperty(
            file, kExtAudioFileProperty_FileLengthFrames, &size, &frames
        ))
        let channels = Int(source.mChannelsPerFrame)
        let rate = Int(source.mSampleRate)
        guard
            channels > 0, frames >= 0,
            frames < 1 << 32 else { throw CAFAudioCodecError.emptyAudio }
        try setClientFormat(file, sampleRate: rate, channels: channels)
        var samples = [Float](repeating: 0, count: Int(frames) * channels)
        var done = 0
        try samples.withUnsafeMutableBufferPointer { buffer in
            // A compressed file may return fewer frames per call than asked.
            while done < Int(frames), let base = buffer.baseAddress {
                var count = UInt32(Int(frames) - done)
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: UInt32(channels),
                        mDataByteSize: count * UInt32(channels * MemoryLayout<Float>.size),
                        mData: base + done * channels
                    )
                )
                try check("read", ExtAudioFileRead(file, &count, &list))
                guard count > 0 else { break }
                done += Int(count)
            }
        }
        return DecodedAudio(
            sampleRate: rate,
            channelCount: channels,
            samples: Array(samples.prefix(done * channels))
        )
    }

    private static func fileDescription(
        _ format: CAFAudioFormat,
        audio: DecodedAudio
    ) -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        description.mSampleRate = Float64(audio.sampleRate)
        description.mChannelsPerFrame = UInt32(audio.channelCount)
        switch format {
        case .pcmFloat32:
            description = floatDescription(
                sampleRate: audio.sampleRate,
                channels: audio.channelCount
            )
        case .alac:
            description.mFormatID = kAudioFormatAppleLossless
            description.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData
            description.mFramesPerPacket = 4096
        case .aac:
            description.mFormatID = kAudioFormatMPEG4AAC
        }
        return description
    }

    private static func floatDescription(
        sampleRate: Int,
        channels: Int
    ) -> AudioStreamBasicDescription {
        let bytes = UInt32(MemoryLayout<Float>.size * channels)
        return AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytes,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytes,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private static func setClientFormat(
        _ file: ExtAudioFileRef,
        sampleRate: Int,
        channels: Int
    ) throws {
        var client = floatDescription(sampleRate: sampleRate, channels: channels)
        try check("client format", ExtAudioFileSetProperty(
            file, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client
        ))
    }

    private static func check(_ operation: String, _ status: OSStatus) throws {
        guard status == noErr else {
            throw CAFAudioCodecError.status(operation: operation, code: status)
        }
    }
}

/// Hands AudioToolbox the bytes of a CAF file through its read callbacks.
nonisolated private final class MemoryAudioSource {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    static let read: AudioFile_ReadProc = { context, position, requested, buffer, actual in
        let source = Unmanaged<MemoryAudioSource>.fromOpaque(context).takeUnretainedValue()
        let start = Int(clamping: max(0, position))
        let count = max(0, min(Int(requested), source.data.count - start))
        source.data.withUnsafeBytes { raw in
            if count > 0, let base = raw.baseAddress {
                buffer.copyMemory(from: base + start, byteCount: count)
            }
        }
        actual.pointee = UInt32(count)
        return noErr
    }

    static let size: AudioFile_GetSizeProc = { context in
        Int64(Unmanaged<MemoryAudioSource>.fromOpaque(context).takeUnretainedValue().data.count)
    }
}
