import AppKit
import Foundation

// Generates both selected app-icon families. Belvedere / Split Signal is
// resampled from its approved checked-in master artwork so the dimensional
// lighting, glow, and monogram geometry cannot drift; Rendered Fold remains a
// deterministic AppKit drawing for the public markdown-preview project. Run
// from the repository root:
//
//   swift scripts/make-icon.swift
//   swift scripts/make-icon.swift --install-mdview
//   swift scripts/make-icon.swift --install-rendered-fold
//
// Both families are generated every run; the --install flags choose which one
// is copied into md-preview/AppIcon.icon. Rendered Fold is installable because
// this fork switches to it if upstream adopts Split Signal for themselves --
// see docs/FORK-NOTES.md.

enum IconDesign: String, CaseIterable {
    case renderedFold = "rendered-fold"
    case splitSignal = "mdview"

    var displayName: String {
        switch self {
        case .renderedFold: "Rendered Fold"
        case .splitSignal: "Split Signal"
        }
    }
}

struct Options {
    var outputRoot = "artwork/app-icons"
    /// Which family to install into the app, if any.
    var install: IconDesign?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())

    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--install-mdview":
            options.install = .splitSignal
        case "--install-rendered-fold":
            options.install = .renderedFold
        case "--output-root":
            guard !arguments.isEmpty else {
                fatalError("--output-root requires a path")
            }
            options.outputRoot = arguments.removeFirst()
        case "--help", "-h":
            print("""
            Usage: swift scripts/make-icon.swift [--output-root PATH] \
            [--install-mdview | --install-rendered-fold]
            """)
            exit(0)
        default:
            fatalError("Unknown argument: \(argument)")
        }
    }

    return options
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func makeContext(side: Int) -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Unable to create \(side) × \(side) bitmap context")
    }

    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
    return context
}

func withGraphicsContext(_ context: CGContext, draw: () -> Void) {
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw()
    NSGraphicsContext.current = previous
}

func fill(
    _ path: NSBezierPath,
    colors: [NSColor],
    angle: CGFloat = 90,
    shadow: Bool = false
) {
    NSGraphicsContext.saveGraphicsState()

    if shadow {
        let iconShadow = NSShadow()
        iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        iconShadow.shadowOffset = NSSize(width: 0, height: -18)
        iconShadow.shadowBlurRadius = 24
        iconShadow.set()
    }

    guard let gradient = NSGradient(colors: colors) else {
        fatalError("Unable to create gradient")
    }
    gradient.draw(in: path, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}


func renderedFoldSurface() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 575, y: 612))
    path.line(to: NSPoint(x: 808, y: 756))
    path.curve(to: NSPoint(x: 858, y: 711), controlPoint1: NSPoint(x: 833, y: 772), controlPoint2: NSPoint(x: 858, y: 746))
    path.line(to: NSPoint(x: 858, y: 329))
    path.curve(to: NSPoint(x: 824, y: 282), controlPoint1: NSPoint(x: 858, y: 307), controlPoint2: NSPoint(x: 846, y: 291))
    path.line(to: NSPoint(x: 624, y: 184))
    path.curve(to: NSPoint(x: 565, y: 228), controlPoint1: NSPoint(x: 594, y: 169), controlPoint2: NSPoint(x: 565, y: 191))
    path.line(to: NSPoint(x: 565, y: 562))
    path.curve(to: NSPoint(x: 575, y: 612), controlPoint1: NSPoint(x: 565, y: 584), controlPoint2: NSPoint(x: 568, y: 600))
    path.close()
    return path
}

func renderedFoldRibbon(y: CGFloat, endY: CGFloat, width: CGFloat) -> NSBezierPath {
    let half = width / 2
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 170, y: y + half))
    path.line(to: NSPoint(x: 430, y: y + half))
    path.curve(to: NSPoint(x: 560, y: endY + half * 0.25), controlPoint1: NSPoint(x: 500, y: y + half), controlPoint2: NSPoint(x: 536, y: endY + half))
    path.line(to: NSPoint(x: 590, y: endY - half * 0.25))
    path.curve(to: NSPoint(x: 430, y: y - half), controlPoint1: NSPoint(x: 542, y: endY - half), controlPoint2: NSPoint(x: 500, y: y - half))
    path.line(to: NSPoint(x: 170, y: y - half))
    path.curve(to: NSPoint(x: 125, y: y), controlPoint1: NSPoint(x: 145, y: y - half), controlPoint2: NSPoint(x: 125, y: y - 25))
    path.curve(to: NSPoint(x: 170, y: y + half), controlPoint1: NSPoint(x: 125, y: y + 25), controlPoint2: NSPoint(x: 145, y: y + half))
    path.close()
    return path
}

func drawRenderedFold(shadow: Bool) {
    let coralTop = color(1.00, 0.53, 0.38)
    let coralBottom = color(0.94, 0.16, 0.27)

    let ribbons = [
        renderedFoldRibbon(y: 654, endY: 570, width: 86),
        renderedFoldRibbon(y: 487, endY: 430, width: 86),
        renderedFoldRibbon(y: 320, endY: 265, width: 86),
    ]
    ribbons.forEach { fill($0, colors: [coralTop, coralBottom], angle: 90, shadow: shadow) }
    fill(renderedFoldSurface(), colors: [coralTop, coralBottom], angle: 90, shadow: shadow)

    let foldHighlight = NSBezierPath()
    foldHighlight.move(to: NSPoint(x: 485, y: 690))
    foldHighlight.curve(to: NSPoint(x: 566, y: 575), controlPoint1: NSPoint(x: 536, y: 681), controlPoint2: NSPoint(x: 560, y: 625))
    foldHighlight.curve(to: NSPoint(x: 584, y: 532), controlPoint1: NSPoint(x: 570, y: 556), controlPoint2: NSPoint(x: 578, y: 540))
    foldHighlight.curve(to: NSPoint(x: 552, y: 594), controlPoint1: NSPoint(x: 571, y: 558), controlPoint2: NSPoint(x: 560, y: 581))
    foldHighlight.curve(to: NSPoint(x: 485, y: 690), controlPoint1: NSPoint(x: 535, y: 635), controlPoint2: NSPoint(x: 514, y: 674))
    foldHighlight.close()
    color(1.00, 0.77, 0.64, 0.68).setFill()
    foldHighlight.fill()
}

func renderMark(_ design: IconDesign, side: Int, shadow: Bool) -> CGImage {
    switch design {
    case .splitSignal:
        return renderSplitSignalReference(side: side)
    case .renderedFold:
        let context = makeContext(side: side)
        withGraphicsContext(context) {
            drawRenderedFold(shadow: shadow)
        }
        guard let image = context.makeImage() else {
            fatalError("Unable to create \(design.displayName) mark")
        }
        return image
    }
}

func drawBackground(_ design: IconDesign) {
    let iconShape = NSBezierPath(
        roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968),
        xRadius: 220,
        yRadius: 220
    )

    let colors: [NSColor]
    switch design {
    case .renderedFold:
        colors = [color(0.31, 0.08, 0.34), color(0.13, 0.02, 0.15)]
    case .splitSignal:
        colors = [color(0.08, 0.48, 0.27), color(0.02, 0.27, 0.16)]
    }
    fill(iconShape, colors: colors, angle: 90)

    if design == .renderedFold {
        NSGraphicsContext.saveGraphicsState()
        iconShape.addClip()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 0, y: 760))
        highlight.line(to: NSPoint(x: 1024, y: 1024))
        highlight.line(to: NSPoint(x: 1024, y: 820))
        highlight.line(to: NSPoint(x: 0, y: 555))
        highlight.close()
        NSColor.white.withAlphaComponent(0.055).setFill()
        highlight.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func makeTransparentSplitSignalMaster() -> CGImage {
    let referenceURL = URL(
        fileURLWithPath: "artwork/app-icons/mdview/design-reference.png",
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
    guard
        let referenceImage = NSImage(contentsOf: referenceURL),
        let source = referenceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fatalError("Unable to load Split Signal design reference at \(referenceURL.path)")
    }

    guard source.width == source.height else {
        fatalError("Split Signal design reference must be square")
    }
    let side = source.width

    let bytesPerRow = side * 4
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
        CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Unable to create Split Signal reference context")
    }

    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

    guard let rawData = context.data else {
        fatalError("Unable to access Split Signal reference pixels")
    }
    let pixels = rawData.bindMemory(to: UInt8.self, capacity: side * bytesPerRow)
    let pixelCount = side * side
    var outside = [Bool](repeating: false, count: pixelCount)
    var queue: [Int] = []
    queue.reserveCapacity(pixelCount / 3)

    func isEdgeBackground(_ index: Int) -> Bool {
        let offset = index * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let brightest = max(red, green, blue)
        let darkest = min(red, green, blue)
        return darkest >= 170 && brightest - darkest <= 36
    }

    func enqueue(_ index: Int) {
        guard !outside[index], isEdgeBackground(index) else { return }
        outside[index] = true
        queue.append(index)
    }

    for coordinate in 0..<side {
        enqueue(coordinate)
        enqueue((side - 1) * side + coordinate)
        enqueue(coordinate * side)
        enqueue(coordinate * side + side - 1)
    }

    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let x = index % side
        let y = index / side
        if x > 0 { enqueue(index - 1) }
        if x + 1 < side { enqueue(index + 1) }
        if y > 0 { enqueue(index - side) }
        if y + 1 < side { enqueue(index + side) }
    }

    for index in queue {
        let offset = index * 4
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
    }

    guard let image = context.makeImage() else {
        fatalError("Unable to create Split Signal reference render")
    }
    return image
}

enum SplitSignalMaster {
    static let image = makeTransparentSplitSignalMaster()
}

func renderSplitSignalReference(side: Int) -> CGImage {
    let source = SplitSignalMaster.image
    let bytesPerRow = side * 4
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
        CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Unable to create Split Signal output context")
    }

    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let image = context.makeImage() else {
        fatalError("Unable to resize Split Signal master")
    }
    return image
}

func renderFullIcon(_ design: IconDesign, side: Int) -> CGImage {
    if design == .splitSignal {
        return renderSplitSignalReference(side: side)
    }

    let context = makeContext(side: side)
    withGraphicsContext(context) {
        drawBackground(design)
    }

    let mark = renderMark(design, side: side, shadow: true)
    context.draw(mark, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

    guard let image = context.makeImage() else {
        fatalError("Unable to create \(design.displayName) icon")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(url.lastPathComponent)")
    }
    try data.write(to: url, options: .atomic)
}

func iconComposerManifest(for design: IconDesign) -> Data {
    let gradient: (top: String, bottom: String)
    switch design {
    case .renderedFold:
        gradient = (
            "srgb:0.31000,0.08000,0.34000,1.00000",
            "srgb:0.13000,0.02000,0.15000,1.00000"
        )
    case .splitSignal:
        gradient = (
            "srgb:0.08000,0.48000,0.27000,1.00000",
            "srgb:0.02000,0.27000,0.16000,1.00000"
        )
    }

    let manifest = """
    {
      "fill" : {
        "linear-gradient" : [
          "\(gradient.top)",
          "\(gradient.bottom)"
        ],
        "orientation" : {
          "start" : {
            "x" : 0.5,
            "y" : 0
          },
          "stop" : {
            "x" : 0.5,
            "y" : 1
          }
        }
      },
      "groups" : [
        {
          "layers" : [
            {
              "glass" : false,
              "image-name" : "AppIconLayer.png",
              "name" : "\(design.displayName)",
              "position" : {
                "scale" : 1,
                "translation-in-points" : [
                  0,
                  0
                ]
              }
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.45
          },
          "translucency" : {
            "enabled" : true,
            "value" : 0.15
          }
        }
      ],
      "supported-platforms" : {
        "circles" : [
          "watchOS"
        ],
        "squares" : "shared"
      }
    }

    """
    return Data(manifest.utf8)
}

func generate(_ design: IconDesign, root: URL) throws {
    let fileManager = FileManager.default
    let designRoot = root.appendingPathComponent(design.rawValue, isDirectory: true)
    let layerDirectory = designRoot.appendingPathComponent("AppIcon.icon/Assets", isDirectory: true)
    let iconsetDirectory = designRoot.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try fileManager.createDirectory(at: layerDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

    try iconComposerManifest(for: design).write(
        to: designRoot.appendingPathComponent("AppIcon.icon/icon.json"),
        options: .atomic
    )

    try writePNG(
        renderMark(design, side: 1024, shadow: false),
        to: layerDirectory.appendingPathComponent("AppIconLayer.png")
    )
    try writePNG(
        renderFullIcon(design, side: 1024),
        to: designRoot.appendingPathComponent("preview-1024.png")
    )

    let iconsetFiles: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for (filename, side) in iconsetFiles {
        try writePNG(
            renderFullIcon(design, side: side),
            to: iconsetDirectory.appendingPathComponent(filename)
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "--convert", "icns",
        "--output", designRoot.appendingPathComponent("AppIcon.icns").path,
        iconsetDirectory.path,
    ]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("iconutil failed for \(design.displayName)")
    }

    print("generated \(design.displayName) in \(designRoot.path)")
}

let options = parseOptions()
let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let outputRoot = URL(fileURLWithPath: options.outputRoot, relativeTo: repositoryRoot).standardizedFileURL

do {
    for design in IconDesign.allCases {
        try generate(design, root: outputRoot)
    }

    if let design = options.install {
        let generatedPackage = outputRoot
            .appendingPathComponent(design.rawValue)
            .appendingPathComponent("AppIcon.icon")
        let installedPackage = repositoryRoot.appendingPathComponent("md-preview/AppIcon.icon")
        let packageFiles = ["icon.json", "Assets/AppIconLayer.png"]
        for relativePath in packageFiles {
            let source = generatedPackage.appendingPathComponent(relativePath)
            let destination = installedPackage.appendingPathComponent(relativePath)
            try Data(contentsOf: source).write(to: destination, options: .atomic)
        }
        print("installed \(design.displayName) package at \(installedPackage.path)")
    }
} catch {
    fputs("icon generation failed: \(error)\n", stderr)
    exit(1)
}
