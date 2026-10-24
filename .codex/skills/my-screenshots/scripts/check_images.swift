import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import zlib

// Check full-screen PNGs and make small sheets for visual inspection.
struct ImageCheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct ImageCheckOptions {
    let directory: URL
    var sheets: URL?
    var report: URL?
    var size: [Int]?
    static let usage =
        "Usage: check_images.swift DIRECTORY [--size WIDTHxHEIGHT] [--sheets DIRECTORY] [--report FILE]"

    init(_ arguments: [String]) throws {
        var directory: URL?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if ["--sheets", "--report", "--size"].contains(argument) {
                index += 1
                guard index < arguments.count else { throw ImageCheckError(Self.usage) }
                let value = arguments[index]
                switch argument {
                case "--sheets": sheets = URL(fileURLWithPath: value)
                case "--report": report = URL(fileURLWithPath: value)
                default:
                    let parts = value.lowercased().split(
                        separator: "x", omittingEmptySubsequences: false)
                    let dimensions = parts.compactMap { Int($0) }
                    guard parts.count == 2, dimensions.count == 2, dimensions.allSatisfy({ $0 > 0 })
                    else {
                        throw ImageCheckError(
                            "--size must have two positive dimensions: WIDTHxHEIGHT")
                    }
                    size = dimensions
                }
            } else {
                guard !argument.hasPrefix("-"), directory == nil else {
                    throw ImageCheckError(Self.usage)
                }
                directory = URL(fileURLWithPath: argument)
            }
            index += 1
        }
        guard let directory else { throw ImageCheckError(Self.usage) }
        self.directory = directory
    }
}

struct ImageCheckReport: Encodable {
    struct Record: Encodable {
        let file: String
        let width: Int
        let height: Int
    }
    var count = 0
    var sizes: [[Int]] = []
    var duplicates: [[String]] = []
    var errors: [String] = []
    var images: [Record] = []
    var contact_sheets: [String] = []
    var failed: Bool { !errors.isEmpty || !duplicates.isEmpty }
}

// ImageIO can display a damaged PNG. Check chunk CRCs before decoding its pixels.
func verifyPNG(_ data: Data) throws {
    guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
        throw ImageCheckError("File is not a PNG.")
    }
    func integer(_ offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    var offset = 8
    while offset <= data.count - 12 {
        let length = Int(integer(offset))
        guard length <= data.count - offset - 12 else { break }
        let crc = data.withUnsafeBytes { bytes in
            crc32(
                0, bytes.bindMemory(to: UInt8.self).baseAddress?.advanced(by: offset + 4),
                uInt(length + 4))
        }
        guard UInt32(crc) == integer(offset + 8 + length) else {
            throw ImageCheckError("PNG chunk checksum failed.")
        }
        if data[offset + 4..<offset + 8].elementsEqual([73, 69, 78, 68]), length == 0 { return }
        offset += length + 12
    }
    throw ImageCheckError("PNG data is incomplete.")
}

// Keep straight RGBA values, including RGB values under fully transparent pixels.
// Drawing into a premultiplied context would lose them and create false duplicates.
func rgbaPixels(_ bitmap: NSBitmapImageRep) throws -> Data {
    guard let bytes = bitmap.bitmapData, !bitmap.isPlanar,
        [.rgb, .gray].contains(bitmap.colorSpace.colorSpaceModel),
        [1, 2, 4, 8, 16].contains(bitmap.bitsPerSample)
    else { throw ImageCheckError("Cannot read PNG pixels.") }
    let rgb = bitmap.colorSpace.colorSpaceModel == .rgb
    let alphaFirst = bitmap.hasAlpha && bitmap.bitmapFormat.contains(.alphaFirst)
    let first = alphaFirst ? 1 : 0
    let alpha = alphaFirst ? 0 : bitmap.samplesPerPixel - 1
    var pixels = Data(count: bitmap.pixelsWide * bitmap.pixelsHigh * 4)
    pixels.withUnsafeMutableBytes { destination in
        let output = destination.bindMemory(to: UInt8.self)
        var samples = [Int](repeating: 0, count: max(4, bitmap.samplesPerPixel))
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let target = (y * bitmap.pixelsWide + x) * 4
                if bitmap.bitsPerSample == 8 {
                    let start = y * bitmap.bytesPerRow + x * bitmap.bitsPerPixel / 8
                    output[target] = bytes[start + first]
                    output[target + 1] = bytes[start + first + (rgb ? 1 : 0)]
                    output[target + 2] = bytes[start + first + (rgb ? 2 : 0)]
                    output[target + 3] = bitmap.hasAlpha ? bytes[start + alpha] : 255
                } else {
                    bitmap.getPixel(&samples, atX: x, y: y)
                    for channel in 0..<bitmap.samplesPerPixel {
                        if bitmap.bitsPerSample < 8 {
                            samples[channel] =
                                samples[channel] * 255 / ((1 << bitmap.bitsPerSample) - 1)
                        }
                        // Pillow exposes 16-bit gray PNGs as integers and clamps on RGBA conversion.
                        else {
                            samples[channel] =
                                rgb || bitmap.hasAlpha
                                ? samples[channel] >> 8 : min(255, samples[channel])
                        }
                    }
                    output[target] = UInt8(samples[first])
                    output[target + 1] = UInt8(samples[first + (rgb ? 1 : 0)])
                    output[target + 2] = UInt8(samples[first + (rgb ? 2 : 0)])
                    output[target + 3] = bitmap.hasAlpha ? UInt8(samples[alpha]) : 255
                }
            }
        }
    }
    return pixels
}

func saveContactSheet(_ items: [(String, CGImage)], directory: URL, number: Int) throws -> String {
    let width = 1040
    let height = 550 * ((items.count + 3) / 4)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw ImageCheckError("Cannot create contact sheet.") }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor(srgbRed: 222 / 255, green: 222 / 255, blue: 222 / 255, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    for (index, item) in items.enumerated() {
        let x = (index % 4) * 260
        let y = (index / 4) * 550
        let scale = min(1, min(240 / Double(item.1.width), 480 / Double(item.1.height)))
        let size = NSSize(
            width: Double(item.1.width) * scale, height: Double(item.1.height) * scale)
        NSImage(cgImage: item.1, size: .zero).draw(
            in: NSRect(
                x: Double(x) + (260 - size.width) / 2, y: Double(height - y) - size.height,
                width: size.width, height: size.height))
        ("\(index + 1): \(item.0)" as NSString).draw(
            in: NSRect(x: x + 5, y: height - y - 545, width: 250, height: 60),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ])
    }
    let filename = "sheet-" + (number < 10 ? "0" : "") + "\(number).jpg"
    let path = directory.appending(path: filename)
    guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    else {
        throw ImageCheckError("Cannot encode contact sheet.")
    }
    try jpeg.write(to: path)
    return path.resolvingSymlinksInPath().path
}

func checkImages(_ options: ImageCheckOptions) throws -> ImageCheckReport {
    let files =
        ((try? FileManager.default.contentsOfDirectory(
            at: options.directory, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "png" }.sorted {
            $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8)
        }
    var report = ImageCheckReport()
    if files.isEmpty { report.errors.append("No PNG files found.") }
    if let directory = options.sheets {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    var hashes: [SHA256.Digest: String] = [:]
    var group: [(String, CGImage)] = []
    for path in files {
        do {
            try autoreleasepool {
                let data = try Data(contentsOf: path)
                try verifyPNG(data)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                    CGImageSourceGetType(source) == UTType.png.identifier as CFString,
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                        as? [CFString: Any],
                    let width = properties[kCGImagePropertyPixelWidth] as? Int,
                    let height = properties[kCGImagePropertyPixelHeight] as? Int,
                    width > 0, height > 0, width <= 178_956_970 / height,
                    let image = CGImageSourceCreateImageAtIndex(
                        source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                    CGImageSourceGetStatus(source) == .statusComplete,
                    CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                    let bitmap = NSBitmapImageRep(data: data)
                else { throw ImageCheckError("Cannot decode complete PNG pixels.") }
                let pixels = try rgbaPixels(bitmap)
                var digest = SHA256()
                digest.update(data: Data("(\(width), \(height))".utf8))
                digest.update(data: pixels)
                let hash = digest.finalize()
                let size = [width, height]
                if !report.sizes.contains(size) { report.sizes.append(size) }
                report.images.append(
                    .init(file: path.lastPathComponent, width: width, height: height))
                if let expected = options.size, size != expected {
                    report.errors.append(
                        "\(path.lastPathComponent): \(size) differs from \(expected).")
                }
                if let previous = hashes[hash] {
                    report.duplicates.append([previous, path.lastPathComponent])
                } else {
                    hashes[hash] = path.lastPathComponent
                }
                if let directory = options.sheets {
                    // Keep only thumbnails between files so a sheet does not retain twelve full screens.
                    let thumbnail =
                        CGImageSourceCreateThumbnailAtIndex(
                            source, 0,
                            [
                                kCGImageSourceCreateThumbnailFromImageAlways: true,
                                kCGImageSourceThumbnailMaxPixelSize: 480,
                            ] as CFDictionary) ?? image
                    group.append((path.lastPathComponent, thumbnail))
                    if group.count == 12 {
                        report.contact_sheets.append(
                            try saveContactSheet(
                                group, directory: directory, number: report.contact_sheets.count + 1
                            ))
                        group.removeAll()
                    }
                }
            }
        } catch { report.errors.append("\(path.lastPathComponent): \(error)") }
    }
    if let directory = options.sheets, !group.isEmpty {
        report.contact_sheets.append(
            try saveContactSheet(
                group, directory: directory, number: report.contact_sheets.count + 1))
    }
    report.count = report.images.count
    report.sizes.sort { $0.lexicographicallyPrecedes($1) }
    if report.sizes.count > 1 {
        report.errors.append("Mixed dimensions. Check the device sets or full-screen captures.")
    }
    if let path = options.report {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(report)
        data.append(10)
        try data.write(to: path)
    }
    return report
}

#if !SCRIPT_TESTS
    @main
    struct ImageCheckCommand {
        static func main() {
            do {
                let arguments = Array(CommandLine.arguments.dropFirst())
                if arguments.contains("--help") || arguments.contains("-h") {
                    print(ImageCheckOptions.usage)
                    return
                }
                let options: ImageCheckOptions
                do { options = try ImageCheckOptions(arguments) } catch {
                    FileHandle.standardError.write(Data("\(error)\n".utf8))
                    exit(2)
                }
                let report = try checkImages(options)
                var summary =
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
                    as? [String: Any] ?? [:]
                summary.removeValue(forKey: "images")
                let data = try JSONSerialization.data(
                    withJSONObject: summary, options: [.sortedKeys, .withoutEscapingSlashes])
                FileHandle.standardOutput.write(data + Data([10]))
                if report.failed { exit(1) }
            } catch {
                FileHandle.standardError.write(Data("Screenshot check: \(error)\n".utf8))
                exit(1)
            }
        }
    }
#endif
