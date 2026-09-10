import Foundation
import AVFoundation
import CoreAudio

// MARK: - 音频采集：BlackHole 2ch → 16bit PCM WAV
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var fileHandle: FileHandle?
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    private var channels: AVAudioChannelCount = 2
    private var silenceSeconds: Double = 0
    private var silentThreshold: Float = 0.0001

    var onLevel: ((Float) -> Void)?      // RMS 0~1
    var onSilence: (() -> Void)?         // 静音超过阈值时长
    var silenceLimit: Double = 60.0      // 连续静音秒数触发

    private let ioLock = NSLock()        // tap 回调与换文件/停止的互斥
    var recordedSeconds: Double { Double(framesWritten) / sampleRate }
    /// 每秒 PCM 字节数（换算 WAV 时长用）
    var pcmBytesPerSecond: Double { sampleRate * Double(channels) * 2 }

    // MARK: 列出可用输入设备
    static func listInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == 0 else { return [] }

        var result: [(AudioDeviceID, String)] = []
        for dev in devices {
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var name: CFString? = nil
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            if AudioObjectGetPropertyData(dev, &nameAddr, 0, nil, &nameSize, &name) == 0, let n = name as String? {
                // 只要输入设备
                var inAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreams,
                    mScope: kAudioObjectPropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain)
                var inSize: UInt32 = 0
                if AudioObjectGetPropertyDataSize(dev, &inAddr, 0, nil, &inSize) == 0, inSize > 0 {
                    result.append((dev, n))
                }
            }
        }
        return result
    }

    static func findBlackHole() -> AudioDeviceID? {
        listInputDevices().first { $0.name.contains("BlackHole") }?.id
    }

    // MARK: 开始
    func start(outputURL: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputURL.deletingLastPathComponent().path) {
            try fm.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: outputURL.path) else {
            throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建录音文件"])
        }
        fileHandle = fh

        // 选 BlackHole 作为输入
        let input = engine.inputNode
        if let bh = Self.findBlackHole(), let unit = input.audioUnit {
            var devID = bh
            AudioUnitSetProperty(unit,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0,
                                 &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "输入设备格式不可用，请检查 BlackHole"])
        }
        sampleRate = format.sampleRate
        channels = format.channelCount

        // WAV 头（尺寸先占位，stop 时回填）
        fh.write(Self.wavHeader(dataBytes: 0, sampleRate: sampleRate, channels: channels))
        framesWritten = 0
        silenceSeconds = 0

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        ioLock.lock()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        // 回填 WAV 头
        if let fh = fileHandle {
            let dataBytes = UInt64(framesWritten) * UInt64(channels) * 2
            fh.seek(toFileOffset: 0)
            fh.write(Self.wavHeader(dataBytes: dataBytes, sampleRate: sampleRate, channels: channels))
            try? fh.close()
        }
        fileHandle = nil
        ioLock.unlock()
    }

    // MARK: 换文件（切歌即分文件：回填旧文件头 → 开新文件，引擎不断）
    func rotate(to newURL: URL) throws {
        ioLock.lock()
        defer { ioLock.unlock() }
        // 旧文件收尾
        if let fh = fileHandle {
            let dataBytes = UInt64(framesWritten) * UInt64(channels) * 2
            fh.seek(toFileOffset: 0)
            fh.write(Self.wavHeader(dataBytes: dataBytes, sampleRate: sampleRate, channels: channels))
            try? fh.close()
        }
        fileHandle = nil
        framesWritten = 0
        silenceSeconds = 0
        // 新文件
        let fm = FileManager.default
        if !fm.fileExists(atPath: newURL.deletingLastPathComponent().path) {
            try fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: newURL.path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: newURL.path) else {
            throw NSError(domain: "AudioCapture", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法创建新歌的录音文件"])
        }
        fh.write(Self.wavHeader(dataBytes: 0, sampleRate: sampleRate, channels: channels))
        fileHandle = fh
    }

    // MARK: 缓冲处理
    private func handle(buffer: AVAudioPCMBuffer) {
        ioLock.lock()
        guard let fh = fileHandle, let chData = buffer.floatChannelData else { ioLock.unlock(); return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { ioLock.unlock(); return }
        let ch = Int(buffer.format.channelCount)

        var rms: Float = 0
        var int16 = [Int16](repeating: 0, count: frames * ch)
        for c in 0..<ch {
            let p = chData[c]
            for i in 0..<frames {
                let v = p[i]
                rms += v * v
                int16[i * ch + c] = Int16(max(-1, min(1, v)) * 32767)
            }
        }
        rms = sqrt(rms / Float(frames * ch))

        int16.withUnsafeBytes { raw in
            fh.write(Data(raw))
        }
        framesWritten += AVAudioFramePosition(frames)
        ioLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onLevel?(min(1, rms * 8))
            if rms < self.silentThreshold {
                self.silenceSeconds += Double(frames) / self.sampleRate
                if self.silenceSeconds >= self.silenceLimit {
                    self.silenceSeconds = 0
                    self.onSilence?()
                }
            } else {
                self.silenceSeconds = 0
            }
        }
    }

    // MARK: WAV 44 字节头
    private static func wavHeader(dataBytes: UInt64, sampleRate: Double, channels: AVAudioChannelCount) -> Data {
        var h = Data(capacity: 44)
        let sr = UInt32(sampleRate)
        let ch = UInt32(channels)
        let blockAlign = ch * 2
        let byteRate = sr * blockAlign
        let dataLen = UInt32(truncatingIfNeeded: dataBytes)
        func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func le16(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        h.append(contentsOf: Array("RIFF".utf8))
        h.append(contentsOf: le32(UInt32(36 + dataLen)))
        h.append(contentsOf: Array("WAVE".utf8))
        h.append(contentsOf: Array("fmt ".utf8))
        h.append(contentsOf: le32(16))
        h.append(contentsOf: le16(1))           // PCM
        h.append(contentsOf: le16(UInt16(ch)))
        h.append(contentsOf: le32(sr))
        h.append(contentsOf: le32(byteRate))
        h.append(contentsOf: le16(UInt16(blockAlign)))
        h.append(contentsOf: le16(16))
        h.append(contentsOf: Array("data".utf8))
        h.append(contentsOf: le32(dataLen))
        return h
    }
}
