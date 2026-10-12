import Foundation

/// Splits a byte stream into lines, keeping empty lines (which `AsyncBytes.lines` drops, but SSE needs).
struct LineSplitter {
    private var buffer: [UInt8] = []

    mutating func push(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            buffer.append(byte)
            return nil
        }
        if buffer.last == UInt8(ascii: "\r") { buffer.removeLast() }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }
}

/// Minimal Server-Sent Events parser: collects `data:` lines and emits the payload at each blank line.
struct EventStreamParser {
    private var dataLines: [String] = []

    mutating func feed(_ line: String) -> String? {
        if line.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines.removeAll() }
            return dataLines.joined(separator: "\n")
        }
        guard line.hasPrefix("data:") else { return nil }
        var value = line.dropFirst(5)
        if value.first == " " { value = value.dropFirst() }
        dataLines.append(String(value))
        return nil
    }
}
