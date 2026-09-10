import Foundation

// MARK: - LAME MP3 编码器（dlopen libmp3lame，app 内置优先）
enum LameEncoder {
    private static var handle: UnsafeMutableRawPointer?

    static func available() -> Bool { load() != nil }

    private static func load() -> UnsafeMutableRawPointer? {
        if let h = handle { return h }
        let candidates: [String] = {
            var list: [String] = []
            if let res = Bundle.main.resourceURL {
                list.append(res.appendingPathComponent("libmp3lame.0.dylib").path)
            }
            if let fw = Bundle.main.privateFrameworksURL {
                list.append(fw.appendingPathComponent("libmp3lame.0.dylib").path)
            }
            list.append(contentsOf: [
                "/opt/homebrew/opt/lame/lib/libmp3lame.0.dylib",
                "/opt/homebrew/lib/libmp3lame.0.dylib",
                "/usr/local/lib/libmp3lame.0.dylib",
            ])
            return list
        }()
        for p in candidates {
            if let h = dlopen(p, RTLD_NOW) { handle = h; return h }
        }
        // 全局查找
        handle = dlopen("libmp3lame.0.dylib", RTLD_NOW)
        return handle
    }

    // MARK: 编码 16bit 交错 PCM → MP3 Data
    static func encode(samples: [Int16], sampleRate: Double, channels: Int, bitrateKbps: Int32 = 320) -> Data? {
        guard let h = load(), channels == 2, !samples.isEmpty else { return nil }

        typealias LameInit = @convention(c) () -> UnsafeMutableRawPointer?
        typealias SetNumChannels = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias SetInSamplerate = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias SetBRate = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias SetQuality = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias SetWriteVbrTag = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
        typealias InitParams = @convention(c) (UnsafeMutableRawPointer?) -> Int32
        typealias EncodeInterleaved = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int16>?, Int32, UnsafeMutablePointer<UInt8>?, Int32) -> Int
        typealias EncodeFlush = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int
        typealias LameClose = @convention(c) (UnsafeMutableRawPointer?) -> Void

        guard
            let fInit = dlsym(h, "lame_init"),
            let fSetCh = dlsym(h, "lame_set_num_channels"),
            let fSetSR = dlsym(h, "lame_set_in_samplerate"),
            let fSetBR = dlsym(h, "lame_set_brate"),
            let fSetQ = dlsym(h, "lame_set_quality"),
            let fSetVbr = dlsym(h, "lame_set_bWriteVbrTag"),
            let fInitP = dlsym(h, "lame_init_params"),
            let fEnc = dlsym(h, "lame_encode_buffer_interleaved"),
            let fFlush = dlsym(h, "lame_encode_flush"),
            let fClose = dlsym(h, "lame_close")
        else { return nil }

        let init_ = unsafeBitCast(fInit, to: LameInit.self)
        let setCh = unsafeBitCast(fSetCh, to: SetNumChannels.self)
        let setSR = unsafeBitCast(fSetSR, to: SetInSamplerate.self)
        let setBR = unsafeBitCast(fSetBR, to: SetBRate.self)
        let setQ = unsafeBitCast(fSetQ, to: SetQuality.self)
        let setVbr = unsafeBitCast(fSetVbr, to: SetWriteVbrTag.self)
        let initP = unsafeBitCast(fInitP, to: InitParams.self)
        let enc = unsafeBitCast(fEnc, to: EncodeInterleaved.self)
        let flush = unsafeBitCast(fFlush, to: EncodeFlush.self)
        let close = unsafeBitCast(fClose, to: LameClose.self)

        guard let gfp = init_() else { return nil }
        defer { close(gfp) }

        _ = setCh(gfp, Int32(channels))
        _ = setSR(gfp, Int32(sampleRate))
        _ = setBR(gfp, bitrateKbps)
        _ = setQ(gfp, 2)
        _ = setVbr(gfp, 0)
        guard initP(gfp) == 0 else { return nil }

        var out = Data()
        let bufSize = 1 << 16
        let mp3buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { mp3buf.deallocate() }

        // 每块 4096 帧/声道
        let chunkFrames = 4096
        var offset = 0
        let totalFrames = samples.count / channels
        while offset < totalFrames {
            let n = min(chunkFrames, totalFrames - offset)
            let written = samples.withUnsafeBufferPointer { buf -> Int in
                let ptr = buf.baseAddress! + offset * channels
                return enc(gfp, UnsafeMutablePointer(mutating: ptr), Int32(n), mp3buf, Int32(bufSize))
            }
            if written > 0 { out.append(mp3buf, count: written) }
            else if written < 0 { return out.isEmpty ? nil : out }
            offset += n
        }
        let tail = flush(gfp, mp3buf, Int32(bufSize))
        if tail > 0 { out.append(mp3buf, count: tail) }
        return out
    }
}
