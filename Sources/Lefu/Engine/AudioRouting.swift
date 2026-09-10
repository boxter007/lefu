import AppKit
import CoreAudio
import Foundation

// MARK: - 采诗通道（多输出设备）配置
// 目标：汽水放歌 → "乐府 采诗通道"(音频 MIDI 设置手工建的多输出设备) → 同时进 BlackHole（乐府录）和扬声器（人听）
// 实测（2026-09-09）：程序化 AudioHardwareCreateAggregateDevice 建不出真·多输出（哪怕带
// kAudioAggregateDeviceIsStackedKey 也是通道拼接，立体声只进主时钟子设备），AMS 的多输出是私有实现。
// 因此本模块只做「复用 + 切默认输出」，设备本体由音频 MIDI 设置手工创建（仅一次，持久生效）。
enum AudioRouting {
    static let aggregateName = "乐府 采诗通道"

    // MARK: 设备探测
    private static func allDevices() -> [AudioDeviceID] {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == 0, size > 0 else { return [] }
        let n = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: n)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
        return ids
    }

    private static func deviceName(_ id: AudioDeviceID) -> String {
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var cf: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf) == 0, let v = cf else { return "" }
        return v as String
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var cf: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf) == 0, let v = cf else { return nil }
        return v as String
    }

    private static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == 0, size > 0 else { return 0 }
        let list = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, list) == 0 else { return 0 }
        var total = 0
        let bufs = UnsafeRawPointer(list).assumingMemoryBound(to: AudioBuffer.self)
        for i in 0..<Int(list.pointee.mNumberBuffers) { total += Int(bufs[i].mNumberChannels) }
        return total
    }

    /// BlackHole 设备（有输入通道、名字以 BlackHole 开头）
    static func blackHole() -> (id: AudioDeviceID, uid: String)? {
        for id in allDevices() {
            let n = deviceName(id)
            if n.hasPrefix("BlackHole"), channels(id, kAudioObjectPropertyScopeInput) > 0 {
                return (id, deviceUID(id) ?? "")
            }
        }
        return nil
    }

    /// 内置扬声器（output 传输类型 BuiltIn）
    static func builtinSpeaker() -> (id: AudioDeviceID, uid: String)? {
        for id in allDevices() {
            guard channels(id, kAudioObjectPropertyScopeOutput) > 0 else { continue }
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var tt: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &tt) == 0, tt == kAudioDeviceTransportTypeBuiltIn else { continue }
            return (id, deviceUID(id) ?? "")
        }
        return nil
    }

    /// 是否已存在"乐府 采诗通道"聚合设备
    static func existingAggregate() -> AudioDeviceID? {
        for id in allDevices() where deviceName(id) == aggregateName {
            return id
        }
        return nil
    }

    static func defaultOutput() -> AudioDeviceID {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return dev
    }

    /// 切换系统默认输出
    static func setDefaultOutput(_ id: AudioDeviceID) throws {
        var dev = id
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, size, &dev)
        guard status == noErr else {
            throw NSError(domain: "AudioRouting", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "切换默认输出失败 (\(status))"])
        }
    }

    /// 一键搭好采诗通道：复用手工建的多输出设备 + 设默认输出。
    /// 设备不存在时打开音频 MIDI 设置引导手工创建（程序建不出真·多输出，见文件头注释）。返回是否动了默认输出
    @discardableResult
    static func setupRoute() throws -> Bool {
        guard let agg = existingAggregate() else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
            throw NSError(domain: "AudioRouting", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "请在音频 MIDI 设置中新建多输出设备：勾选扬声器与 BlackHole 2ch，主设备选扬声器，BlackHole 勾漂移修正，并命名为「\(aggregateName)」"])
        }
        var changed = false
        if defaultOutput() != agg {
            try setDefaultOutput(agg)
            changed = true
        }
        return changed
    }

    /// 恢复：默认输出切回内置扬声器
    static func restoreRoute() throws {
        guard let spk = builtinSpeaker() else {
            throw NSError(domain: "AudioRouting", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "未找到内置扬声器"])
        }
        try setDefaultOutput(spk.id)
    }

    /// 默认输出是否已接通采诗通道（是聚合设备且包含 BlackHole）
    static func isDefaultOutputRouted() -> Bool {
        let cur = defaultOutput()
        var ta = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                            mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
        var tt: UInt32 = 0
        var tsize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(cur, &ta, 0, nil, &tsize, &tt) == 0,
              tt == kAudioDeviceTransportTypeAggregate else { return false }
        guard let bhUID = blackHole()?.uid else { return false }
        // 读聚合的子设备，包含 BlackHole 才算真正接通
        // kAudioAggregateDevicePropertyActiveSubDevices 未导出到 Swift，用 FourCC 'grps'
        var a = AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x67727073),
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(cur, &a, 0, nil, &size) == 0, size > 0 {
            let n = Int(size) / MemoryLayout<AudioDeviceID>.size
            var ids = [AudioDeviceID](repeating: 0, count: n)
            if AudioObjectGetPropertyData(cur, &a, 0, nil, &size, &ids) == 0 {
                for id in ids where deviceName(id).hasPrefix("BlackHole") { return true }
            }
        }
        return deviceName(cur) == aggregateName
    }

    // MARK: 实时监听
    /// 监听「设备列表」与「默认输出」变化（CoreAudio 系统级回调）。
    /// 用户在音频 MIDI 设置里手工建好多输出设备 / 切输出后，UI 状态实时跟上，不用重启或手点重新检查。
    static func startWatching(_ onChange: @escaping () -> Void) {
        let queue = DispatchQueue(label: "com.jingjing.lefu.route-watch")
        var devicesAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, queue) { _, _ in
            onChange()
        }
        var defaultAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, queue) { _, _ in
            onChange()
        }
    }
}
