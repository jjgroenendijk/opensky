// Bink movie decode through libavcodec: video packets to `MoviePicture`, audio
// packets to interleaved Float PCM. `BinkMovie` frames the packets; the codec setup
// follows docs/formats/bink.md.

import CFFmpeg
import Foundation
import OpenSkyFormatsAudio
import OpenSkyFormatsCore

nonisolated public final class BinkVideoDecoder {
    private let session: FFmpegCodecSession

    public init(movie: BinkMovie) throws {
        session = try FFmpegCodecSession(codec: AV_CODEC_ID_BINKVIDEO) { context in
            context.pointee.codec_tag = movie.codecTag
            context.pointee.width = Int32(movie.width)
            context.pointee.height = Int32(movie.height)
            try FFmpegCodecSession.attachExtradata(
                littleEndian(movie.videoFlags), to: context
            )
        }
    }

    /// The picture of one video packet. A frame builds on the one before it, so every
    /// frame decodes, in order, even when it is not shown.
    public func decode(packet: Data) throws -> MoviePicture? {
        try session.send(packet)
        var picture: MoviePicture?
        try session.receiveFrames { picture = try Self.picture(of: $0) }
        return picture
    }

    private static func picture(of frame: UnsafeMutablePointer<AVFrame>) throws -> MoviePicture {
        let format = frame.pointee.format
        // Bink decodes to YUV420P, or YUVA420P with an alpha plane this player ignores.
        guard
            format == AV_PIX_FMT_YUV420P.rawValue || format == AV_PIX_FMT_YUVA420P.rawValue
        else { throw FFmpegDecoderError.unsupportedPixelFormat(format) }
        let width = Int(frame.pointee.width)
        let height = Int(frame.pointee.height)
        let chroma = (width: (width + 1) / 2, height: (height + 1) / 2)
        let planes = frame.pointee.data
        let strides = frame.pointee.linesize
        return try MoviePicture(
            width: width,
            height: height,
            luma: plane(planes.0, stride: strides.0, width: width, height: height),
            chromaBlue: plane(
                planes.1, stride: strides.1, width: chroma.width, height: chroma.height
            ),
            chromaRed: plane(
                planes.2, stride: strides.2, width: chroma.width, height: chroma.height
            ),
            isFullRange: frame.pointee.color_range == AVCOL_RANGE_JPEG
        )
    }

    /// Copies one plane into packed rows.
    private static func plane(
        _ base: UnsafeMutablePointer<UInt8>?, stride: Int32, width: Int, height: Int
    ) throws -> Data {
        guard let base, Int(stride) >= width, width > 0, height > 0 else {
            throw FFmpegDecoderError.unsupportedPixelFormat(-1)
        }
        var packed = Data(count: width * height)
        packed.withUnsafeMutableBytes { raw in
            guard let target = raw.baseAddress else { return }
            for row in 0 ..< height {
                memcpy(target + row * width, base + row * Int(stride), width)
            }
        }
        return packed
    }
}

nonisolated public final class BinkAudioDecoder {
    private let session: FFmpegCodecSession
    private var resampler: FFmpegResampler?

    public init(track: BinkAudioTrack, movie: BinkMovie) throws {
        let codec = track.usesDCT ? AV_CODEC_ID_BINKAUDIO_DCT : AV_CODEC_ID_BINKAUDIO_RDFT
        session = try FFmpegCodecSession(codec: codec) { context in
            context.pointee.sample_rate = Int32(track.sampleRate)
            av_channel_layout_default(&context.pointee.ch_layout, Int32(track.channelCount))
            // The audio decoder reads the movie's revision letter from the codec tag.
            try FFmpegCodecSession.attachExtradata(littleEndian(movie.codecTag), to: context)
        }
    }

    /// Interleaved Float PCM at the track's rate and channel count.
    public func decode(packet: Data) throws -> [Float] {
        try session.send(packet)
        return try session.receiveSamples(resampler: &resampler)
    }

    /// The PCM the decoder still holds once the last packet was sent.
    public func flush() throws -> [Float] {
        try session.sendEnd()
        return try session.receiveSamples(resampler: &resampler)
    }

    /// The whole track of a short movie, such as the startup logo.
    public static func decodeTrack(
        _ trackIndex: Int, of movie: BinkMovie, data: Data
    ) throws -> DecodedAudio {
        guard movie.audioTracks.indices.contains(trackIndex) else {
            throw BinkMovieError.malformed("no audio track \(trackIndex)")
        }
        let track = movie.audioTracks[trackIndex]
        let decoder = try BinkAudioDecoder(track: track, movie: movie)
        var samples: [Float] = []
        for frame in movie.frames.indices {
            let packets = try movie.packets(ofFrame: frame, in: data)
            if let packet = packets.audio[trackIndex] {
                try samples.append(contentsOf: decoder.decode(packet: packet))
            }
        }
        try samples.append(contentsOf: decoder.flush())
        return DecodedAudio(
            sampleRate: track.sampleRate, channelCount: track.channelCount, samples: samples
        )
    }
}

nonisolated private func littleEndian(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
}
