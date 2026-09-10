import CoreAudio
import Foundation

func allDevices() -> [AudioDeviceID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == 0 else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
    return ids
}
func name(_ id: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var cf: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf)
    return (cf as String?) ?? "?"
}
func uid(_ id: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var cf: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf)
    return (cf as String?) ?? "?"
}

guard let agg = allDevices().first(where: { name($0) == "乐府 采诗通道" }) else { print("无聚合"); exit(0) }
print("聚合 id=\(agg) uid=\(uid(agg))")

// 'lsts' FullSubDeviceList → CFArray of dict
var a = AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x6c737473), mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
let st1 = AudioObjectGetPropertyDataSize(agg, &a, 0, nil, &size)
print("'lsts' size=\(size) status=\(st1)")
if st1 == 0, size > 0 {
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<CFArray>.alignment)
    defer { ptr.deallocate() }
    let st = AudioObjectGetPropertyData(agg, &a, 0, nil, &size, ptr)
    print("读数据 status=\(st)")
    if st == 0, let arr = ptr.load(as: CFArray.self) as? [[String: Any]] {
        for d in arr {
            let u = d[kAudioSubDeviceUIDKey] as? String ?? "?"
            let drift = d[kAudioSubDeviceDriftCompensationKey] as? Int ?? -1
            print("  子设备 uid=\(u) drift=\(drift)")
        }
    }
}

// 'grps' ActiveSubDevices → array of AudioDeviceID
var b = AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x67727073), mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size2: UInt32 = 0
let st2 = AudioObjectGetPropertyDataSize(agg, &b, 0, nil, &size2)
print("'grps' size=\(size2) status=\(st2)")
if st2 == 0, size2 > 0 {
    var ids = [AudioDeviceID](repeating: 0, count: Int(size2)/MemoryLayout<AudioDeviceID>.size)
    var s2 = size2
    let st = AudioObjectGetPropertyData(agg, &b, 0, nil, &s2, &ids)
    if st == 0 {
        for id in ids { print("  活动子设备: \(name(id)) uid=\(uid(id))") }
    } else { print("'grps' 读数据 status=\(st)") }
}

// BlackHole 与扬声器直查
for id in allDevices() {
    let n = name(id)
    if n.hasPrefix("BlackHole") || n.contains("扬声器") || n == "U32R59x" {
        print("设备: \(n) uid=\(uid(id))")
    }
}
