import AppKit
import Foundation

struct ScriptTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
final class ScriptTests {
    var count = 0

    func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw ScriptTestFailure(description: "FAIL: " + message) }
        count += 1
    }

    func rejects(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return false
        } catch { return true }
    }

    func write(_ root: URL, _ name: String, _ text: String) throws {
        let path = root.appending(path: name)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: path)
    }

    func git(_ root: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ScriptTestFailure(description: "Git fixture setup failed.")
        }
    }

    func candidateTests(_ directory: URL) throws {
        let fixture = directory.appending(path: "hash fixture")
        try write(fixture, "a.txt", "alpha\n")
        try write(fixture, "a/file", "beta\0bytes")
        try write(fixture, "z space", "gamma")
        try write(fixture, "café", "coffee")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.appending(path: "link").path, withDestinationPath: "./a.txt")
        let paths = ["a.txt", "a/file", "z space", "café", "link", "missing"].sorted {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        }
        // These hashes were recorded with the Python implementation before its removal.
        try expect(
            try BackupCandidate.digest(root: fixture, paths: paths)
                == "5ea170c4645caebade54b88bfb7a759da7f8611c71dc75c7d28ba74414c9f157",
            "source hash byte contract")
        try write(fixture, BackupCandidate.receipt, "ignored")
        try write(fixture, "a/" + BackupCandidate.receipt, "also ignored")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.appending(path: "broken").path, withDestinationPath: "missing")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.appending(path: "folder-link").path, withDestinationPath: "a")
        // Foundation creates decomposed Unicode filenames on macOS.
        try expect(
            try BackupCandidate.archiveDigest(fixture)
                == "419f2721f8319c39cfeb1647134eb114e069f2fadd7b8fce016a67db3bf4fd47",
            "archive component order, links, and receipt exclusions")
        let large = Data(repeating: 42, count: 2_100_000)
        try large.write(to: fixture.appending(path: "large"))
        try expect(
            try BackupCandidate.digest(root: fixture, paths: ["large"])
                == "227480ef6019026d5cab2f8d6b7bef722a9b88b91aeaa05424ffe6151fe2e12d",
            "chunked hash")

        let root = directory.appending(path: "git fixture")
        try write(root, ".gitignore", "build/\nignored.txt\n")
        try write(root, "source.swift", "original")
        try git(root, ["init", "-q"])
        try git(root, ["add", "."])
        let candidate = BackupCandidate(root: root)
        let original = try candidate.source()
        let record = root.appending(path: "build/candidate.json").path
        try candidate.run(["capture", record])
        try candidate.run(["check", record])
        try write(root, "ignored.txt", "ignored")
        try write(root, "sites/index.html", "website")
        try expect(
            try candidate.source() == original,
            "ignored and website files do not invalidate candidate")
        try write(root, "source.swift", "changed")
        try expect(
            rejects { try candidate.run(["check", record]) },
            "changed source rejects saved candidate")
        try write(root, "source.swift", "original")
        try write(root, "new.swift", "untracked")
        try expect(try candidate.source() != original, "untracked source participates")
        try FileManager.default.removeItem(at: root.appending(path: "new.swift"))
        try FileManager.default.removeItem(at: root.appending(path: "source.swift"))
        try expect(try candidate.source() != original, "deleted tracked file participates")
        try write(root, "source.swift", "original")
        let archive = root.appending(path: "build/Test.xcarchive")
        try write(archive, "Products/App", "archive bytes")
        try candidate.run(["attest", archive.path, record])
        try candidate.run(["verify-archive", archive.path])
        try expect(
            !rejects { try candidate.run(["verify-archive", archive.path]) },
            "saved archive receipt remains readable")
        try write(archive, "Products/App", "mutated bytes")
        try expect(
            rejects { try candidate.run(["verify-archive", archive.path]) },
            "changed archive rejects receipt")
        try FileManager.default.removeItem(at: archive.appending(path: BackupCandidate.receipt))
        try expect(
            rejects { try candidate.run(["verify-archive", archive.path]) },
            "missing receipt blocks release")
        try write(root, "build/candidate.json", "{broken")
        try expect(
            rejects { try candidate.run(["check", record]) }, "malformed candidate blocks release")
        try expect(
            rejects { try candidate.run(["attest", archive.path, record]) },
            "malformed evidence blocks attestation")
        try expect(rejects { try candidate.run(["capture"]) }, "missing arguments fail")
        try expect(rejects { try candidate.run(["unknown", record]) }, "unknown mode fails")
    }

    func deviceTests() throws {
        let settings = [
            "GoogleBackupClientID": "synthetic-client",
            "GoogleBackupCallbackScheme": "synthetic-callback",
        ]
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: settings, format: .xml, options: 0)
        let device: [String: Any] = [
            "releaseOnDevice": true, "clientID": "synthetic-client",
            "callbackScheme": "synthetic-callback",
        ]
        func check(_ record: [String: Any], configuration: Data = configuration) throws {
            try checkBackupDevice(
                credentials: JSONSerialization.data(withJSONObject: record),
                configuration: configuration)
        }
        try expect(
            !rejects { try check(["clientID": "synthetic-client", "deviceCheck": device]) },
            "matching physical Release evidence")
        for value: Any in [false, 1, "true", NSNull()] {
            var invalid = device
            invalid["releaseOnDevice"] = value
            try expect(
                rejects { try check(["clientID": "synthetic-client", "deviceCheck": invalid]) },
                "device evidence requires a true JSON boolean")
        }
        for key in ["clientID", "callbackScheme", "releaseOnDevice"] {
            var missing = device
            missing.removeValue(forKey: key)
            try expect(
                rejects { try check(["clientID": "synthetic-client", "deviceCheck": missing]) },
                "missing device field: " + key)
        }
        try expect(
            rejects { try check(["clientID": "other-client", "deviceCheck": device]) },
            "credential account client must match")
        var mismatch = device
        mismatch["callbackScheme"] = "other-callback"
        try expect(
            rejects { try check(["clientID": "synthetic-client", "deviceCheck": mismatch]) },
            "callback must match configured client")
        try expect(rejects { try check(["deviceCheck": NSNull()]) }, "null device evidence fails")
        try expect(
            rejects { try check([:], configuration: Data("bad plist".utf8)) }, "bad plist fails")
        try expect(
            rejects {
                try checkBackupDevice(
                    credentials: Data("bad json".utf8), configuration: configuration)
            }, "bad credential JSON fails")
    }

    func simulatorTests() throws {
        let data = Data(
            #"""
            {"devices": {
              "com.apple.CoreSimulator.SimRuntime.watchOS-27-0": [{"name":"iPhone watch","state":"Booted","udid":"watch"}],
              "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                {"name":"iPhone unavailable","state":"Shutdown","isAvailable":false,"udid":"unavailable"},
                {"name":"iPad","state":"Shutdown","udid":"ipad"},
                {"name":"iPhone 17 Pro","state":"Shutdown","isAvailable":true,"udid":"cloud-first"}],
              "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name":"iPhone 17","state":"Shutdown","udid":"fallback"},
                {"name":"iPad","state":"Booted","udid":"booted"}]
            }}
            """#.utf8)
        try expect(
            try selectSimulator(data: data, arguments: ["local", "iPhone 17", "27.0"]) == "booted",
            "local mode prefers booted iOS device across runtimes")
        try expect(
            try selectSimulator(data: data, arguments: ["cloud"]) == "cloud-first",
            "cloud mode uses first available iOS iPhone in JSON order")
        let shutdown = Data(
            String(decoding: data, as: UTF8.self).replacing("Booted", with: "Shutdown").utf8)
        try expect(
            try selectSimulator(data: shutdown, arguments: ["local", "iPhone 17", "27.0"])
                == "fallback", "named device/runtime fallback")
        try expect(
            try selectSimulator(data: shutdown, arguments: ["local", "iPhone 17", "27.1"]) == "",
            "local no-match leaves existing Make error")
        try expect(
            rejects {
                _ = try selectSimulator(data: Data(#"{"devices":{}}"#.utf8), arguments: ["cloud"])
            }, "cloud no-match blocks archive")
        try expect(
            rejects { _ = try selectSimulator(data: Data("invalid".utf8), arguments: ["cloud"]) },
            "invalid simulator JSON")
        try expect(
            rejects { _ = try selectSimulator(data: data, arguments: []) },
            "invalid selector arguments")
    }

    func png(
        _ path: URL, width: Int = 2, height: Int = 2, pixels: [UInt8],
        profile: NSColorSpace = .deviceRGB
    ) throws {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bitmapFormat: [.alphaNonpremultiplied], bytesPerRow: 0,
                bitsPerPixel: 32),
            let bytes = bitmap.bitmapData
        else { throw ScriptTestFailure(description: "Cannot make image fixture.") }
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<4 {
                    bytes[y * bitmap.bytesPerRow + x * 4 + channel] =
                        pixels[(y * width + x) * 4 + channel]
                }
            }
        }
        let tagged = bitmap.retagging(with: profile) ?? bitmap
        guard let data = tagged.representation(using: .png, properties: [:]) else {
            throw ScriptTestFailure(description: "Cannot encode image fixture.")
        }
        try data.write(to: path)
    }

    func imageTests(_ directory: URL) throws {
        let root = directory.appending(path: "images")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try expect(
            try checkImages(ImageCheckOptions([root.path])).errors == ["No PNG files found."],
            "empty image directory")
        for size in ["0x2", "-2x2", "2x", "2x2x2", "bad"] {
            try expect(
                rejects { _ = try ImageCheckOptions([root.path, "--size", size]) },
                "invalid expected image size")
        }
        let pixels: [UInt8] = [
            123, 124, 125, 0, 123, 124, 125, 1, 123, 124, 125, 127, 1, 2, 3, 255,
        ]
        // This fixture was encoded by Pillow. It is independent of the Swift encoder.
        guard
            let reference = Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGklEQVR4nGOsrqllYGBgYGRiYGCob2tr+wcAH60EiJzN8X8AAAAASUVORK5CYII="
            ),
            let referenceBitmap = NSBitmapImageRep(data: reference)
        else { throw ScriptTestFailure(description: "Cannot read reference image.") }
        try expect(
            try rgbaPixels(referenceBitmap) == Data(pixels), "legacy RGBA fixture pixel contract")
        let formats: [(String, String, [UInt8])] = [
            (
                "RGB",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVR4nGPkUbJwsnAGAANZASWOEMgpAAAAAElFTkSuQmCC",
                [12, 34, 56, 255, 78, 90, 123, 255]
            ),
            (
                "gray",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGOo/w8AAgABf//RyUkAAAAASUVORK5CYII=",
                [127, 127, 127, 255, 255, 255, 255, 255]
            ),
            (
                "mono",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQAAAADcWUInAAAACklEQVR4nGNwAAAAQgBBKTf07wAAAABJRU5ErkJggg==",
                [0, 0, 0, 255, 255, 255, 255, 255]
            ),
            (
                "gray alpha",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGOsZmBiBAAB+wCAJTgL0wAAAABJRU5ErkJggg==",
                [123, 123, 123, 0, 125, 125, 125, 1]
            ),
            (
                "gray 16",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAAAAACB2fwVAAAADUlEQVR4nGNgYGRkAAAACgADMKFJuAAAAABJRU5ErkJggg==",
                [1, 1, 1, 255, 255, 255, 255, 255]
            ),
            (
                "palette",
                "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAA/wDSh+9xAAAAAnRSTlMAAQGU/a4AAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC",
                [255, 0, 0, 0, 0, 255, 0, 1]
            ),
        ]
        for (name, base64, expected) in formats {
            guard let data = Data(base64Encoded: base64), let bitmap = NSBitmapImageRep(data: data)
            else {
                throw ScriptTestFailure(description: "Cannot read " + name + " reference.")
            }
            try verifyPNG(data)
            try expect(
                try rgbaPixels(bitmap) == Data(expected), name + " pixels match legacy conversion")
        }
        let first = root.appending(path: "a.png")
        try png(first, pixels: pixels)
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: first)) else {
            throw ScriptTestFailure(description: "Missing PNG fixture.")
        }
        try expect(
            try rgbaPixels(bitmap) == Data(pixels),
            "straight RGBA preserves transparent and partial alpha channels")
        try png(root.appending(path: "b.png"), pixels: pixels, profile: .displayP3)
        try expect(
            try Data(contentsOf: first) != Data(contentsOf: root.appending(path: "b.png")),
            "duplicate fixture has distinct encoded PNG bytes")
        let duplicate = try checkImages(ImageCheckOptions([root.path, "--size", "2X2"]))
        try expect(
            duplicate.duplicates == [["a.png", "b.png"]],
            "equal pixel values with different profiles are duplicates")
        var different = pixels
        different[0] += 1
        try png(root.appending(path: "b.png"), pixels: different)
        try expect(
            try checkImages(ImageCheckOptions([root.path])).duplicates.isEmpty,
            "transparent RGB difference is not an exact duplicate")
        try png(root.appending(path: "c.png"), width: 1, height: 1, pixels: [10, 20, 30, 255])
        try write(root, "bad.png", "not a PNG")
        let valid = try Data(contentsOf: first)
        try valid.dropLast(6).write(to: root.appending(path: "truncated.png"))
        var corrupt = valid
        corrupt[29] ^= 1
        try corrupt.write(to: root.appending(path: "corrupt.png"))
        let sheets = directory.appending(path: "sheets")
        let reportPath = directory.appending(path: "report/images.json")
        let report = try checkImages(
            ImageCheckOptions([
                root.path, "--size", "2x2", "--sheets", sheets.path, "--report", reportPath.path,
            ]))
        try expect(
            report.count == 3 && report.sizes == [[1, 1], [2, 2]], "PNG count and sorted dimensions"
        )
        try expect(
            report.failed && report.errors.count == 5,
            "wrong size, mixed dimensions, bad format, checksum, and truncation fail")
        try expect(
            report.contact_sheets.count == 1 && report.contact_sheets[0].hasPrefix("/"),
            "absolute contact sheet path")
        let sheetData = try Data(contentsOf: sheets.appending(path: "sheet-01.jpg"))
        let sheet = NSBitmapImageRep(data: sheetData)
        try expect(
            sheet?.pixelsWide == 1040 && sheet?.pixelsHigh == 550,
            "four-column contact sheet dimensions")
        let json =
            try JSONSerialization.jsonObject(with: Data(contentsOf: reportPath)) as? [String: Any]
        try expect(
            Set(json?.keys.map { $0 } ?? [])
                == Set(["count", "sizes", "duplicates", "errors", "images", "contact_sheets"]),
            "existing report field contract")
        let many = directory.appending(path: "many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<13 {
            try png(
                many.appending(path: "\(index).png"), width: 1, height: 1,
                pixels: [UInt8(index), 0, 0, 255])
        }
        let paged = try checkImages(
            ImageCheckOptions([many.path, "--sheets", directory.appending(path: "paged").path]))
        try expect(
            !paged.failed && paged.contact_sheets.count == 2,
            "twelve images per sheet, including final partial sheet")
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "clinical script tests \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tests = ScriptTests()
        try tests.candidateTests(directory)
        try tests.deviceTests()
        try tests.simulatorTests()
        try tests.imageTests(directory)
        print("Passed \(tests.count) repository script checks.")
    }
}
