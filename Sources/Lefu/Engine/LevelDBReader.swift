import Foundation

// MARK: - 只读的 LevelDB / Snappy 解析（用于读取其他 App 的本地缓存）
// 喜马拉雅（Electron）把当前曲目的「歌词/AI 文稿」明文写在 Chromium 的
// localStorage（LevelDB）里。本文件实现读取它所需的最小解析：
//   - Snappy 解压（LevelDB 的块压缩）
//   - SSTable（.ldb）：footer → index block → data block
//   - WAL（.log）：日志记录 → WriteBatch → key/value
// 全程只读；任何一步失败都返回 nil/空，绝不影响录制主流程。
enum LevelDBSnappy {
    static func varint(_ d: [UInt8], _ start: Int) -> (Int, Int)? {
        var p = start, shift = 0, res = 0
        while p < d.count && shift <= 63 {
            let b = Int(d[p]); p += 1
            res |= (b & 0x7f) << shift
            if b & 0x80 == 0 { return (res, p) }
            shift += 7
        }
        return nil
    }

    static func decode(_ d: [UInt8], at pos: Int) -> [UInt8]? {
        guard let (ulen, p0) = varint(d, pos), ulen > 0, ulen <= 64 << 20 else { return nil }
        var p = p0
        var out = [UInt8](); out.reserveCapacity(ulen)
        while p < d.count && out.count < ulen {
            let tag = d[p]; p += 1
            let t = tag & 3
            switch t {
            case 0:
                var len = Int(tag >> 2)
                if len < 60 { len += 1 }
                else {
                    let nb = len - 59
                    guard p + nb <= d.count else { return nil }
                    var v = 0
                    for i in 0..<nb { v |= Int(d[p + i]) << (8 * i) }
                    len = v + 1; p += nb
                }
                guard p + len <= d.count else { return nil }
                out.append(contentsOf: d[p..<p + len]); p += len
            case 1:
                let len = Int((tag >> 2) & 0x7) + 4
                guard p < d.count else { return nil }
                let off = (Int(tag >> 5) << 8) | Int(d[p]); p += 1
                guard off > 0, off <= out.count else { return nil }
                for _ in 0..<len { out.append(out[out.count - off]) }
            case 2:
                let len = Int(tag >> 2) + 1
                guard p + 2 <= d.count else { return nil }
                let off = Int(d[p]) | (Int(d[p + 1]) << 8); p += 2
                guard off > 0, off <= out.count else { return nil }
                for _ in 0..<len { out.append(out[out.count - off]) }
            default:
                let len = Int(tag >> 2) + 1
                guard p + 4 <= d.count else { return nil }
                let off = Int(d[p]) | (Int(d[p + 1]) << 8) | (Int(d[p + 2]) << 16) | (Int(d[p + 3]) << 24); p += 4
                guard off > 0, off <= out.count else { return nil }
                for _ in 0..<len { out.append(out[out.count - off]) }
            }
        }
        return out.count == ulen ? out : nil
    }
}

enum LevelDBReader {
    struct Handle { let offset: Int; let size: Int }

    static func handle(_ d: [UInt8], _ start: Int) -> (Handle, Int)? {
        guard let (o, p1) = LevelDBSnappy.varint(d, start),
              let (s, p2) = LevelDBSnappy.varint(d, p1) else { return nil }
        return (Handle(offset: o, size: s), p2)
    }

    static func readBlock(_ d: [UInt8], _ h: Handle) -> [UInt8]? {
        guard h.offset >= 0, h.size >= 0, h.offset + h.size < d.count else { return nil }
        let ctype = d[h.offset + h.size]
        let body = Array(d[h.offset..<h.offset + h.size])
        switch ctype {
        case 0: return body
        case 1: return LevelDBSnappy.decode(body, at: 0)
        default: return nil
        }
    }

    static func entries(_ body: [UInt8]) -> [(key: [UInt8], value: [UInt8])] {
        guard body.count >= 4 else { return [] }
        let n = body.count
        let num = Int(body[n - 4]) | (Int(body[n - 3]) << 8) | (Int(body[n - 2]) << 16) | (Int(body[n - 1]) << 24)
        let dataEnd = n - 4 * (num + 1)
        guard dataEnd >= 0, dataEnd <= n else { return [] }
        var p = 0
        var out: [(key: [UInt8], value: [UInt8])] = []
        while p < dataEnd {
            guard let (shared, p1) = LevelDBSnappy.varint(body, p),
                  let (nonShared, p2) = LevelDBSnappy.varint(body, p1),
                  let (vlen, p3) = LevelDBSnappy.varint(body, p2) else { break }
            p = p3
            guard p + nonShared + vlen <= body.count else { break }
            var key = Array(body[p..<p + nonShared]); p += nonShared
            let value = Array(body[p..<p + vlen]); p += vlen
            if shared > 0, let last = out.last?.key, shared <= last.count {
                key = Array(last[0..<shared]) + key
            }
            out.append((key, value))
        }
        return out
    }

    /// 读取一个 .ldb（SSTable）里的所有 key/value
    static func sstableEntries(_ d: [UInt8]) -> [(key: [UInt8], value: [UInt8])] {
        guard d.count > 48 else { return [] }
        let footer = Array(d[(d.count - 48)..<d.count])
        guard let (_, p1) = handle(footer, 0), let (ih, _) = handle(footer, p1),
              let indexBody = readBlock(d, ih) else { return [] }
        var out: [(key: [UInt8], value: [UInt8])] = []
        for (_, v) in entries(indexBody) {
            guard let (dh, _) = handle(v, 0), let db = readBlock(d, dh) else { continue }
            out.append(contentsOf: entries(db))
        }
        return out
    }

    /// 读取一个 .log（WAL）里的所有 key/value
    static func logEntries(_ d: [UInt8]) -> [(key: [UInt8], value: [UInt8])] {
        let blockSize = 32768
        var records: [[UInt8]] = []
        var pending: [UInt8] = []
        var blockStart = 0
        while blockStart < d.count {
            var p = blockStart
            let blockEnd = min(d.count, blockStart + blockSize)
            while p + 7 <= blockEnd {
                let length = Int(d[p + 4]) | (Int(d[p + 5]) << 8)
                let type = d[p + 6]
                if type == 0 { break }
                let ps = p + 7
                guard ps + length <= blockEnd else { break }
                let payload = Array(d[ps..<ps + length])
                p = ps + length
                switch type {
                case 1:
                    if !pending.isEmpty { pending = [] }
                    records.append(payload)
                case 2:
                    pending = payload
                case 3:
                    pending.append(contentsOf: payload)
                case 4:
                    pending.append(contentsOf: payload)
                    records.append(pending); pending = []
                default: break
                }
            }
            blockStart += blockSize
        }
        var out: [(key: [UInt8], value: [UInt8])] = []
        for rec in records { out.append(contentsOf: batchEntries(rec)) }
        return out
    }

    static func batchEntries(_ rec: [UInt8]) -> [(key: [UInt8], value: [UInt8])] {
        guard rec.count >= 12 else { return [] }
        let count = Int(rec[8]) | (Int(rec[9]) << 8) | (Int(rec[10]) << 16) | (Int(rec[11]) << 24)
        var p = 12
        var out: [(key: [UInt8], value: [UInt8])] = []
        var i = 0
        while i < count && p < rec.count {
            let t = rec[p]; p += 1
            guard let (klen, p1) = LevelDBSnappy.varint(rec, p) else { break }
            p = p1
            guard p + klen <= rec.count else { break }
            let key = Array(rec[p..<p + klen]); p += klen
            if t == 1 {
                guard let (vlen, p2) = LevelDBSnappy.varint(rec, p) else { break }
                p = p2
                guard p + vlen <= rec.count else { break }
                out.append((key, Array(rec[p..<p + vlen]))); p += vlen
            } else {
                out.append((key, []))
            }
            i += 1
        }
        return out
    }

    /// Chromium localStorage 的值：首字节 0 = UTF-16LE，1 = Latin-1/UTF-8
    static func decodeLocalStorageValue(_ v: [UInt8]) -> String? {
        guard let enc = v.first else { return nil }
        let body = Array(v.dropFirst())
        if enc == 0 {
            var units: [UInt16] = []; units.reserveCapacity(body.count / 2)
            var i = 0
            while i + 1 < body.count {
                units.append(UInt16(body[i]) | (UInt16(body[i + 1]) << 8)); i += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
        return String(decoding: body, as: UTF8.self)
    }

    /// 读取目录下所有 .ldb/.log 里解码后的 localStorage 字符串
    static func localStorageStrings(in dir: URL) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [String] = []
        for name in names where name.hasSuffix(".ldb") || name.hasSuffix(".log") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { continue }
            let bytes = [UInt8](data)
            let pairs = name.hasSuffix(".ldb") ? sstableEntries(bytes) : logEntries(bytes)
            for (_, value) in pairs {
                if let s = decodeLocalStorageValue(value) { out.append(s) }
            }
        }
        return out
    }
}
