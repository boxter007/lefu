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

guard let bh = allDevices().first(where: { name($0).hasPrefix("BlackHole") }) else { print("无 BlackHole"); exit(1) }

var peak: Float = 0
let lock = NSLock()

let proc: AudioDeviceIOProc = { _, _, _, _, inInputData, _, _ in
    let ablPtr = UnsafePointer<AudioBufferList>(inInputData)
    let bufs = UnsafeRawPointer(ablPtr).assumingMemoryBound(to: AudioBuffer.self)
    for b in 0..<Int(ablPtr.pointee.mNumberBuffers) {
        let n = Int(bufs[b].mDataByteSize) / MemoryLayout<Float32>.size
        if let d = bufs[b].mData {
            let f = d.assumingMemoryBound(to: Float32.self)
            for i in 0..<n {
                let v = abs(f[i])
                if v > peak { lock.lock(); peak = max(peak, v); lock.unlock() }
            }
        }
    }
    return noErr
}

var procID: AudioDeviceIOProcID? = nil
print("建 IOProc status=\(AudioDeviceCreateIOProcID(bh, proc, nil, &procID))")
print("启动 status=\(AudioDeviceStart(bh, proc))")

Thread.sleep(forTimeInterval: 8.0)

AudioDeviceStop(bh, proc)
if let p = procID { AudioDeviceDestroyIOProcID(bh, p) }
print("BlackHole 输入峰值: \(peak)")
print(peak > 0.01 ? "RESULT: 音频已到达 BlackHole ✓" : "RESULT: BlackHole 没收到音频 ✗")
