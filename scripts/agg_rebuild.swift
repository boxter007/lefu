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
func transport(_ id: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var tt: UInt32 = 0
    var s = UInt32(MemoryLayout<UInt32>.size)
    _ = AudioObjectGetPropertyData(id, &a, 0, nil, &s, &tt)
    let b0 = UInt8((tt >> 24) & 0xFF), b1 = UInt8((tt >> 16) & 0xFF), b2 = UInt8((tt >> 8) & 0xFF), b3 = UInt8(tt & 0xFF)
    return "\(String(UnicodeScalar(b0)))\(String(UnicodeScalar(b1)))\(String(UnicodeScalar(b2)))\(String(UnicodeScalar(b3))) (\(tt))"
}
func outCh(_ id: AudioDeviceID) -> Int {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == 0, size > 0 else { return 0 }
    let list = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
    defer { list.deallocate() }
    guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, list) == 0 else { return 0 }
    var t = 0
    let bufs = UnsafeRawPointer(list).assumingMemoryBound(to: AudioBuffer.self)
    for i in 0..<Int(list.pointee.mNumberBuffers) { t += Int(bufs[i].mNumberChannels) }
    return t
}
func setDefaultOutput(_ id: AudioDeviceID) -> OSStatus {
    var dev = id
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, size, &dev)
}
func uid(_ id: AudioDeviceID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var cf: CFString? = nil
    var size = UInt32(MemoryLayout<CFString?>.size)
    _ = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf)
    return (cf as String?) ?? "?"
}

// 1. 盘点所有同名聚合
let aggs = allDevices().filter { name($0) == "乐府 采诗通道" }
print("发现 \(aggs.count) 个同名聚合:")
for g in aggs { print("  id=\(g) transport=\(transport(g)) outCh=\(outCh(g))") }

// 2. 全部销毁（先切走默认输出）
if let spk = allDevices().first(where: { name($0) == "Mac mini扬声器" }) {
    print("切默认输出→扬声器 status=\(setDefaultOutput(spk))")
}
for g in aggs {
    let st = AudioHardwareDestroyAggregateDevice(g)
    print("销毁 id=\(g) status=\(st)")
}
Thread.sleep(forTimeInterval: 0.5)
let remain = allDevices().filter { name($0) == "乐府 采诗通道" }
print("销毁后剩余: \(remain.count)")

// 3. 重建：扬声器为主时钟，BlackHole 漂移补偿
let spk = allDevices().first { name($0) == "Mac mini扬声器" }!
let bh  = allDevices().first { name($0).hasPrefix("BlackHole") }!
let desc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "乐府 采诗通道",
    kAudioAggregateDeviceUIDKey: "com.jingjing.lefu.route2" as CFString,  // 换 UID 避缓存
    kAudioAggregateDeviceIsPrivateKey: false,
    kAudioAggregateDeviceMasterSubDeviceKey: uid(spk) as CFString,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: uid(spk), kAudioSubDeviceDriftCompensationKey: 0],
        [kAudioSubDeviceUIDKey: uid(bh), kAudioSubDeviceDriftCompensationKey: 1],
    ] as CFArray,
]
var newID = AudioDeviceID(0)
let st = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newID)
print("重建 status=\(st) id=\(newID) transport=\(transport(newID)) outCh=\(outCh(newID))")
print("设默认输出→新聚合 status=\(setDefaultOutput(newID))")
print("当前默认输出: \(name(allDevices().first { $0 == newID } ?? 0))")
