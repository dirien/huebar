import Foundation
import Testing

@testable import HueBar

struct PathDataTests {
    @Test func parsesEveryCommandKind() {
        let commands = PathData.parse("M10 20 L-30 40.5 C1 2 3 4 5 6 Q7 8 9 10 Z")
        #expect(
            commands == [
                .move(CGPoint(x: 10, y: 20)),
                .line(CGPoint(x: -30, y: 40.5)),
                .cubic(CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6)),
                .quad(CGPoint(x: 7, y: 8), CGPoint(x: 9, y: 10)),
                .close,
            ]
        )
    }

    #if canImport(AppKit)
        @Test(arguments: PhosphorIcon.all.map(\.name))
        func generatedIconsFitTheirGrid(name: String) throws {
            let icon = try #require(PhosphorIcon.all.first { $0.name == name }?.icon)
            let paths = [icon.regular, icon.bold, icon.fill, icon.duotoneBackground].compactMap { $0 }
            #expect(!paths.isEmpty)
            // Bézier control points may poke slightly outside the 256×256 grid; the drawn shape doesn't.
            let grid = CGRect(x: 0, y: 0, width: 256, height: 256).insetBy(dx: -4, dy: -4)
            for path in paths {
                #expect(!path.isEmpty)
                #expect(grid.contains(path.boundingRect))
            }
        }
    #endif
}
