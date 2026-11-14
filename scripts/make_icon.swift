// Draws the Ductus app icon and writes every size macOS needs into
// Ductus/Assets.xcassets/AppIcon.appiconset.
//
// The icon: a pen stroke sweeping over a row of keys. The stroke is drawn with
// a simulated broad-nib pen (the path drawn many times along a slanted nib),
// which gives the thick and thin lines of calligraphy. No fonts are used.
//
// Usage: swift scripts/make_icon.swift [output folder]   (default: the app's asset catalog)
// Add --preview to also write a 1024 px preview.png in the output folder.
import AppKit
import SwiftUI

let arguments = CommandLine.arguments.dropFirst()
let preview = arguments.contains("--preview")
let outputPath = arguments.first { !$0.hasPrefix("--") } ?? "Ductus/Assets.xcassets/AppIcon.appiconset"
let output = URL(fileURLWithPath: outputPath)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Draws `path` with a broad nib `width` wide, held at `angle` degrees.
func nib(_ context: inout GraphicsContext, _ path: Path, width: CGFloat, angle: Double, color: Color, line: CGFloat) {
    let radians = angle * .pi / 180
    let dx = cos(radians), dy = -sin(radians)
    let steps = max(8, Int(width / (line * 0.45)))
    for i in 0...steps {
        let k = (CGFloat(i) / CGFloat(steps) - 0.5) * width
        context.stroke(path.offsetBy(dx: dx * k, dy: dy * k), with: .color(color),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
    }
}

func keycap(_ context: inout GraphicsContext, _ rect: CGRect, radius: CGFloat) {
    // Side, then top face with a soft highlight.
    context.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: rect.height * 0.08), cornerRadius: radius),
                 with: .color(.white.opacity(0.32)))
    context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .linearGradient(
        Gradient(colors: [.white, Color(hex: 0xE6ECF5)]),
        startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
}

/// The icon on a 1024 canvas. `simple` is for 16 and 32 px: three bigger keys
/// and a bolder stroke, since fine detail turns to mush that small.
struct Icon: View {
    var simple = false

    var body: some View {
        let tile: CGFloat = 824
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x4B3FB8), Color(hex: 0x1C8C9A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            Canvas { context, _ in
                let amber = Color(hex: 0xF2B544)
                // Keys along the bottom.
                let count = simple ? 3 : 4
                let gap: CGFloat = simple ? 40 : 26
                let key: CGFloat = simple ? 200 : 142
                let rowWidth = CGFloat(count) * key + CGFloat(count - 1) * gap
                let top: CGFloat = simple ? 520 : 548
                for i in 0..<count {
                    let rect = CGRect(x: (tile - rowWidth) / 2 + CGFloat(i) * (key + gap), y: top, width: key, height: key)
                    keycap(&context, rect, radius: key * 0.2)
                }
                // The stroke: rises from the left, loops over, and sweeps right.
                var stroke = Path()
                stroke.move(to: CGPoint(x: 136, y: 420))
                stroke.addCurve(to: CGPoint(x: 410, y: 236), control1: CGPoint(x: 150, y: 230), control2: CGPoint(x: 310, y: 150))
                stroke.addCurve(to: CGPoint(x: 676, y: 318), control1: CGPoint(x: 510, y: 330), control2: CGPoint(x: 590, y: 400))
                nib(&context, stroke, width: simple ? 96 : 68, angle: 40, color: .white, line: simple ? 7 : 3.4)
                // Arrowhead where the pen leaves the page: the direction of the stroke.
                var tip = Path()
                let end = CGPoint(x: 714, y: 290)
                tip.move(to: CGPoint(x: end.x - 64, y: end.y - 24))
                tip.addLine(to: end)
                tip.addLine(to: CGPoint(x: end.x - 34, y: end.y + 56))
                context.stroke(tip, with: .color(amber),
                               style: StrokeStyle(lineWidth: simple ? 34 : 22, lineCap: .round, lineJoin: .round))
            }
            .frame(width: tile, height: tile)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        }
        .frame(width: tile, height: tile)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func png(_ view: some View, pixels: Int) throws -> Data {
    let renderer = ImageRenderer(content: view)
    renderer.scale = CGFloat(pixels) / 1024
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

@MainActor func run() throws {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    // macOS icon slots: (points, scale).
    let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    var images: [[String: String]] = []
    for (points, scale) in slots {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(Icon(simple: pixels <= 32), pixels: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output.appendingPathComponent("Contents.json"))
    if preview {
        try png(Icon(), pixels: 1024).write(to: output.appendingPathComponent("preview.png"))
        try png(Icon(simple: true), pixels: 1024).write(to: output.appendingPathComponent("preview-small.png"))
    }
    print("Wrote app icon to \(output.path)")
}

try MainActor.assumeIsolated { try run() }
