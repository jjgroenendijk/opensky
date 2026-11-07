// One opened libavcodec decoder with its packet and frame: packets in, frames out.
// The WMA and Bink decoders share it; no ffmpeg pointer leaves the decoder files.
// See docs/decisions/ffmpeg-audio.md.

import CFFmpeg
import Foundation

/// Sole owner of the ffmpeg allocations behind one session. The session's initializer
/// builds it as a local, because Swift skips a class deinit when its initializer throws.
@safe nonisolated private final class FFmpegCodecResources {
    var context: UnsafeMutablePointer<AVCodecContext>?
    var packet: UnsafeMutablePointer<AVPacket>?
    var frame: UnsafeMutablePointer<AVFrame>?

    deinit {
        // avcodec_free_context also frees the extradata buffer handed to the context.
        unsafe avcodec_free_context(&context)
        unsafe av_packet_free(&packet)
        unsafe av_frame_free(&frame)
    }
}

@safe nonisolated final class FFmpegCodecSession {
    /// ffmpeg reports "send me more input" and "fully drained" as negative status values.
    private enum Status {
        static let again = -Int32(EAGAIN)
        /// `AVERROR_EOF`: the negated packed tag `'E','O','F',' '`.
        static let endOfFile = -0x2046_4F45
    }

    private let resources: FFmpegCodecResources
    private let context: UnsafeMutablePointer<AVCodecContext>
    private let packet: UnsafeMutablePointer<AVPacket>
    private let frame: UnsafeMutablePointer<AVFrame>

    /// `configure` sets the codec fields the container gives before the codec opens.
    init(
        codec id: AVCodecID,
        configure: (UnsafeMutablePointer<AVCodecContext>) throws -> Void
    ) throws {
        guard let codec = unsafe avcodec_find_decoder(id) else {
            throw FFmpegDecoderError.decoderUnavailable
        }
        let owned = FFmpegCodecResources()
        guard let context = unsafe avcodec_alloc_context3(codec) else {
            throw FFmpegDecoderError.allocationFailed("AVCodecContext")
        }
        unsafe owned.context = unsafe context
        try unsafe configure(context)
        let status = unsafe avcodec_open2(context, codec, nil)
        guard status >= 0 else { throw FFmpegDecoderError.openFailed(code: status) }
        guard let packet = unsafe av_packet_alloc() else {
            throw FFmpegDecoderError.allocationFailed("AVPacket")
        }
        unsafe owned.packet = unsafe packet
        guard let frame = unsafe av_frame_alloc() else {
            throw FFmpegDecoderError.allocationFailed("AVFrame")
        }
        unsafe owned.frame = unsafe frame
        resources = owned
        unsafe self.context = unsafe context
        unsafe self.packet = unsafe packet
        unsafe self.frame = unsafe frame
    }

    /// Sends one packet. An empty packet sends nothing.
    func send(_ data: Data) throws {
        guard !data.isEmpty else { return }
        // libavcodec copies the payload into its own padded, reference-counted buffer, so
        // the borrowed pointer only has to stay valid across avcodec_send_packet.
        let status = unsafe data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            unsafe packet.pointee.data = unsafe UnsafeMutableRawPointer(mutating: base)
                .assumingMemoryBound(to: UInt8.self)
            unsafe packet.pointee.size = Int32(raw.count)
            defer {
                unsafe packet.pointee.data = nil
                unsafe packet.pointee.size = 0
            }
            return unsafe avcodec_send_packet(context, packet)
        }
        guard status >= 0 else { throw FFmpegDecoderError.decodeFailed(code: status) }
    }

    /// Tells the decoder no packet follows, so it hands out what it still holds.
    func sendEnd() throws {
        let status = unsafe avcodec_send_packet(context, nil)
        guard status >= 0 || status == Status.endOfFile else {
            throw FFmpegDecoderError.decodeFailed(code: status)
        }
    }

    /// Hands each finished frame to `body`. The frame is only valid during the call.
    func receiveFrames(_ body: (UnsafeMutablePointer<AVFrame>) throws -> Void) throws {
        while true {
            let status = unsafe avcodec_receive_frame(context, frame)
            if status == Status.again || status == Status.endOfFile {
                return
            }
            guard status >= 0 else { throw FFmpegDecoderError.decodeFailed(code: status) }
            // The frame's buffers are recycled on the next receive, so unref on every path.
            defer { unsafe av_frame_unref(frame) }
            try unsafe body(frame)
        }
    }

    /// Every finished audio frame as interleaved Float PCM. `resampler` is built from the
    /// first frame and kept for the next calls.
    func receiveSamples(resampler: inout FFmpegResampler?) throws -> [Float] {
        var samples: [Float] = []
        try unsafe receiveFrames { frame in
            let converter = try unsafe resampler ?? FFmpegResampler(matching: frame)
            resampler = converter
            try unsafe samples.append(contentsOf: converter.interleavedFloats(from: frame))
        }
        return samples
    }

    /// Drops buffered state so the decoder can restart at another packet.
    func reset() {
        unsafe avcodec_flush_buffers(context)
    }

    /// Copies codec-private bytes into an ffmpeg-owned buffer. libavcodec requires
    /// `AV_INPUT_BUFFER_PADDING_SIZE` readable zero bytes past the end, and takes ownership:
    /// `avcodec_free_context` releases this allocation.
    static func attachExtradata(
        _ extradata: Data,
        to context: UnsafeMutablePointer<AVCodecContext>
    ) throws {
        guard !extradata.isEmpty else { return }
        let size = extradata.count
        guard let buffer = unsafe av_mallocz(size + Int(AV_INPUT_BUFFER_PADDING_SIZE)) else {
            throw FFmpegDecoderError.allocationFailed("extradata")
        }
        unsafe extradata.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                unsafe memcpy(buffer, base, size)
            }
        }
        unsafe context.pointee.extradata = unsafe buffer.assumingMemoryBound(to: UInt8.self)
        unsafe context.pointee.extradata_size = Int32(size)
    }
}
