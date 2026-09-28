import Foundation

struct PBMImage {
    let width: Int
    let height: Int
    var rows: [[UInt8]]

    static func parse(_ data: Data) throws -> PBMImage {
        var index = 0

        func readToken() throws -> String {
            while index < data.count {
                let byte = data[index]
                if byte == 35 { // '#'
                    while index < data.count, data[index] != 10 { index += 1 }
                }
                if index >= data.count { break }
                let b = data[index]
                if b == 9 || b == 10 || b == 13 || b == 32 {
                    index += 1
                } else {
                    break
                }
            }
            let start = index
            while index < data.count {
                let b = data[index]
                if b == 9 || b == 10 || b == 13 || b == 32 { break }
                index += 1
            }
            guard start < index else { throw PrinterServiceError.invalidPBM("Missing token") }
            return String(decoding: data[start..<index], as: UTF8.self)
        }

        let magic = try readToken()
        guard magic == "P4" else { throw PrinterServiceError.invalidPBM("Only P4 PBM is supported") }
        guard let width = Int(try readToken()), let height = Int(try readToken()), width > 0, height > 0 else {
            throw PrinterServiceError.invalidPBM("Invalid dimensions")
        }

        while index < data.count {
            let b = data[index]
            if b == 9 || b == 10 || b == 13 || b == 32 {
                index += 1
            } else {
                break
            }
        }

        let rowBytes = (width + 7) / 8
        let payloadBytes = rowBytes * height
        guard data.count - index >= payloadBytes else {
            throw PrinterServiceError.invalidPBM("PBM payload is truncated")
        }

        var rows: [[UInt8]] = []
        rows.reserveCapacity(height)
        for row in 0..<height {
            let start = index + row * rowBytes
            let end = start + rowBytes
            rows.append(Array(data[start..<end]))
        }
        return PBMImage(width: width, height: height, rows: rows)
    }

    mutating func normalize(to paperWidth: Int, flipHorizontal: Bool, flipVertical: Bool) {
        let outputRowBytes = paperWidth / 8

        rows = rows.map { source in
            var row = [UInt8](repeating: 0, count: outputRowBytes)
            let sourceLimit = min(source.count, outputRowBytes)
            row.replaceSubrange(0..<sourceLimit, with: source.prefix(sourceLimit))
            return row
        }

        if flipHorizontal {
            rows = rows.map { row in
                row.reversed().map { CatPrinterProtocol.reverseBits($0) }
            }
        }

        if flipVertical {
            rows.reverse()
        }
    }
}
