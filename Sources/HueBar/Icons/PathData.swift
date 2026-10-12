import Foundation

enum PathCommand: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)
    case quad(CGPoint, CGPoint)
    case close
}

/// Parses the simplified path data written by Scripts/generate-phosphor-icons.py:
/// absolute `M x y`, `L x y`, `C x1 y1 x2 y2 x y`, `Q x1 y1 x y` and `Z`, separated by spaces.
enum PathData {
    static func parse(_ data: String) -> [PathCommand] {
        var commands: [PathCommand] = []
        var op: Character?
        var numbers: [CGFloat] = []

        func flush() {
            guard let op else { return }
            func point(_ i: Int) -> CGPoint { CGPoint(x: numbers[i], y: numbers[i + 1]) }
            switch (op, numbers.count) {
            case ("M", 2): commands.append(.move(point(0)))
            case ("L", 2): commands.append(.line(point(0)))
            case ("C", 6): commands.append(.cubic(point(0), point(2), point(4)))
            case ("Q", 4): commands.append(.quad(point(0), point(2)))
            case ("Z", 0): commands.append(.close)
            default: assertionFailure("Malformed path command \(op) with \(numbers.count) values")
            }
        }

        for token in data.split(separator: " ") {
            guard let first = token.first else { continue }
            if first.isLetter {
                flush()
                op = first
                numbers.removeAll(keepingCapacity: true)
                if token.count > 1, let value = Double(token.dropFirst()) {
                    numbers.append(CGFloat(value))
                }
            } else if let value = Double(token) {
                numbers.append(CGFloat(value))
            }
        }
        flush()
        return commands
    }
}
