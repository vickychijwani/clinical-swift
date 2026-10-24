import CryptoKit
import Foundation

struct CandidateError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// Bind backup checks to source, configuration, and archive bytes.
struct BackupCandidate {
    let root: URL
    static let receipt = "clinical-backup-receipt.json"

    func source() throws -> [String: String] {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        git.currentDirectoryURL = root
        let output = Pipe()
        git.standardOutput = output
        try git.run()
        // Drain the pipe before waiting. A large file list can fill the pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0, let names = String(data: data, encoding: .utf8) else {
            throw CandidateError("Cannot list candidate source files.")
        }
        let paths = names.split(separator: "\0").map(String.init).filter { !$0.hasPrefix("sites/") }
        // Compare UTF-8 bytes so Unicode normalization does not merge distinct Git paths.
        let unique = Set(paths.map { Data($0.utf8) }).sorted { $0.lexicographicallyPrecedes($1) }
        return [
            "source": try Self.digest(
                root: root, paths: unique.map { String(decoding: $0, as: UTF8.self) }),
            "configuration": "Release",
        ]
    }

    static func digest(root: URL, paths: [String]) throws -> String {
        var digest = SHA256()
        for relative in paths {
            let path = root.appending(path: relative)
            digest.update(data: Data((relative + "\0").utf8))
            let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: path.path)
                // pathlib removes empty and dot components from link targets.
                let parts = target.split(separator: "/").filter { $0 != "." }
                let prefix =
                    target.hasPrefix("//") && !target.hasPrefix("///")
                    ? "//" : target.hasPrefix("/") ? "/" : ""
                let normalized = prefix + parts.joined(separator: "/")
                digest.update(data: Data((normalized.isEmpty ? "." : normalized).utf8))
            } else if attributes?[.type] as? FileAttributeType == .typeRegular {
                let file = try FileHandle(forReadingFrom: path)
                defer { try? file.close() }
                while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
                    digest.update(data: chunk)
                }
            } else {
                digest.update(data: Data("<deleted>".utf8))
            }
        }
        return digest.finalize().map { String($0, radix: 16).leftPaddedHex }.joined()
    }

    static func archiveDigest(_ root: URL) throws -> String {
        var paths: [String] = []
        func visit(_ directory: URL, prefix: String) throws {
            for path in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                ])
            {
                let values = try path.resourceValues(forKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                ])
                let relative = prefix + path.lastPathComponent
                let isLink = values.isSymbolicLink == true
                // rglob does not descend through directory links. File links are hashed as links.
                let targetType =
                    (try? FileManager.default.attributesOfItem(
                        atPath: path.resolvingSymlinksInPath().path))?[.type] as? FileAttributeType
                if path.lastPathComponent != receipt
                    && (values.isRegularFile == true || isLink && targetType == .typeRegular)
                {
                    paths.append(relative)
                }
                if values.isDirectory == true && !isLink {
                    try visit(path, prefix: relative + "/")
                }
            }
        }
        try visit(root, prefix: "")
        // Python Path ordering compares path components, rather than the joined path.
        paths.sort {
            $0.split(separator: "/").map { Array($0.utf8) }.lexicographicallyPrecedes(
                $1.split(separator: "/").map { Array($0.utf8) },
                by: { $0.lexicographicallyPrecedes($1) })
        }
        return try digest(root: root, paths: paths)
    }

    func run(_ arguments: [String]) throws {
        guard let mode = arguments.first,
            arguments.count == (mode == "attest" ? 3 : 2),
            ["capture", "check", "attest", "verify-archive"].contains(mode)
        else {
            throw CandidateError(
                "Usage: backup_candidate.swift capture|check|attest|verify-archive PATH [CANDIDATE]"
            )
        }
        let path = URL(fileURLWithPath: arguments[1])
        var current = try source()
        func matches(_ saved: URL, message: String) throws {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: saved))
            guard let record = value as? [String: String], record == current else {
                throw CandidateError(message)
            }
        }
        func write(_ destination: URL) throws {
            try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys]).write(
                to: destination)
        }
        switch mode {
        case "capture":
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(path)
        case "check":
            try matches(
                path, message: "Candidate source changed during verification or archive creation.")
        case "attest":
            try matches(
                URL(fileURLWithPath: arguments[2]),
                message: "Archive source changed during its build.")
            current["archive"] = try Self.archiveDigest(path)
            try write(path.appending(path: Self.receipt))
        default:
            current["archive"] = try Self.archiveDigest(path)
            try matches(
                path.appending(path: Self.receipt),
                message: "Archive does not match this candidate. Create a new archive.")
        }
    }
}

extension String {
    fileprivate var leftPaddedHex: String { count == 1 ? "0" + self : self }
}

#if !SCRIPT_TESTS
    @main
    struct CandidateCommand {
        static func main() {
            do {
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .deletingLastPathComponent()
                try BackupCandidate(root: root).run(Array(CommandLine.arguments.dropFirst()))
            } catch {
                FileHandle.standardError.write(Data("Backup release gate: \(error)\n".utf8))
                exit(1)
            }
        }
    }
#endif
