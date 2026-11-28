import Foundation

@main
struct ArchitectureTests {
    static func main() throws {
        var count = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ArchitectureError("FAIL: \(message)") }
            count += 1
        }
        let source = ###"""
            // import EventKit
            /* import SQLiteData /* import SwiftUI */ */
            let text = "import GRDB"
            let raw = ##"import ClinicalPersistence"##
            let interpolated = "\(value ?? "import SwiftUI")"
            let rawInterpolated = #"\#(value ?? "import GRDB")"#
            let multiline = """
                import UIKit
                """
            let rawMultiline = #"""
                import AppKit
                """#
            #if os(iOS)
            @_exported import struct Foundation.Date
            #else
            @preconcurrency import
                EventKit
            #endif
            internal import SQLiteData
            @testable import ClinicalPersistence
            """###
        let imports = sourceImports(source)
        try expect(
            imports.map(\.module) == [
                "Foundation", "EventKit", "SQLiteData", "ClinicalPersistence",
            ], "attributed, scoped, conditional imports; ignore comments and strings")
        try expect(imports.first?.line == 14, "report the import line")
        let model = "Sources/ClinicalModels/Patient.swift"
        try expect(
            checkImports(path: model, source: source).count == 3,
            "reject all forbidden conditional model imports")
        try expect(
            checkImports(path: model, source: "import Foundation\nimport Dependencies").isEmpty,
            "allow model imports")
        try expect(
            !checkImports(
                path: "Sources/ClinicalPersistence/Record.swift", source: "import EventKit"
            ).isEmpty, "reject persistence platform integration")
        try expect(
            !checkImports(path: "ClinicalShared/Card.swift", source: "import ClinicalPersistence")
                .isEmpty, "check shared widget sources")
        try expect(
            !checkImports(
                path: "Other/Shared.swift", source: "import ClinicalPersistence", widgetMember: true
            ).isEmpty, "check project-selected widget sources")
        try expect(
            !checkImports(
                path: "clinical-swift/patients/views/PatientAvatar.swift",
                source: "import SQLiteData"
            ).isEmpty, "display restriction")
        try expect(
            checkImports(
                path: "clinical-swift/patients/views/PatientsView.swift",
                source: "import SQLiteData"
            ).isEmpty, "observed outer screen exception")
        try expect(
            checkImports(
                path: "clinical-swift/appointments/views/AppointmentDetailsView.swift",
                source: "import SQLiteData"
            ).isEmpty, "preview setup exception")
        try expect(
            !checkImports(
                path: "clinical-swift/appointments/views/AppointmentDetailsView.swift",
                source: "import ClinicalPersistence"
            ).isEmpty, "preview exception is limited to SQLiteData")
        try expect(
            checkImports(path: "clinical-swift/utils/Binding.swift", source: "import SwiftUI")
                .isEmpty, "utils is not a zero-dependency layer")

        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let graph = try packageGraph(root)
        try expect(try checkPackage(graph).isEmpty, "current package graph")
        var brokenGraph = graph
        brokenGraph.targets[0].dependencies = [.name("ClinicalPersistence")]
        try expect(
            try checkPackage(brokenGraph).contains {
                $0.contains("ClinicalModels dependency ClinicalPersistence")
            }, "forbidden graph dependency without an import")
        brokenGraph.targets[0].path = "clinical-swift"
        try expect(
            try checkPackage(brokenGraph).contains { $0.contains("standard layout") },
            "custom source path")
        var productGraph = graph
        productGraph.products = [
            PackageGraph.Product(name: "ClinicalModels", targets: ["ClinicalPersistence"])
        ]
        try expect(
            try checkPackage(productGraph).contains { $0.contains("only its own target") },
            "product cannot expose another layer")

        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "architecture-index-\(UUID())")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for folder in [
            "Sources/ClinicalModels", "Sources/ClinicalPersistence", "Tests/ClinicalDataTests",
            "clinical-swift", "ClinicalWidget", "ClinicalShared", "clinical-swift.xcodeproj",
        ] {
            try FileManager.default.createDirectory(
                at: fixture.appending(path: folder), withIntermediateDirectories: true)
            try Data().write(to: fixture.appending(path: folder + "/.keep"))
        }
        try FileManager.default.copyItem(
            at: root.appending(path: "Package.swift"), to: fixture.appending(path: "Package.swift"))
        try FileManager.default.copyItem(
            at: root.appending(path: projectPath), to: fixture.appending(path: projectPath))
        func write(_ path: String, _ text: String) throws {
            try text.write(to: fixture.appending(path: path), atomically: true, encoding: .utf8)
        }
        func stage() throws { _ = try command(fixture, "git", ["add", "."]) }
        _ = try command(fixture, "git", ["init", "--quiet"])
        try write(model, "import Foundation\n")
        try stage()
        try expect(try checkArchitecture(root: fixture, staged: true).isEmpty, "clean index")
        try write(model, "import SwiftUI\n")
        try stage()
        try write(model, "import Foundation\n")
        try expect(
            try checkArchitecture(root: fixture, staged: false).isEmpty,
            "unstaged source correction")
        try expect(
            try checkArchitecture(root: fixture, staged: true).contains {
                $0.contains("import SwiftUI")
            }, "index violation cannot be hidden by working source")
        try stage()
        let manifest = try String(
            contentsOf: fixture.appending(path: "Package.swift"), encoding: .utf8)
        try write(
            "Package.swift",
            manifest.replacing(
                "dependencies: [.product(name: \"Dependencies\", package: \"swift-dependencies\")]",
                with: "dependencies: [\"ClinicalPersistence\"]"))
        try stage()
        try write("Package.swift", manifest)
        try expect(
            try checkArchitecture(root: fixture, staged: true).contains {
                $0.contains("ClinicalModels dependency ClinicalPersistence")
            }, "read manifest from index")
        try stage()
        try write("ClinicalShared/Extra.swift", "#if os(iOS)\nimport ClinicalPersistence\n#endif\n")
        try expect(
            try checkArchitecture(root: fixture, staged: false).contains {
                $0.contains("Extra.swift:2:")
            }, "include new shared sources")
        try FileManager.default.removeItem(
            at: fixture.appending(path: "ClinicalShared/Extra.swift"))
        // OpenStep ASCII plist parser coverage: comments, escapes, arrays, dicts, data, and errors.
        let samplePlist = #"""
            // !$*UTF8*$!
            {
                /* block comment */
                unquoted = foo_bar$1/2:3.4-5;
                quoted = "line1\n\t\"quote\"\\slash\U0041\UD83D\UDE00\101";
                list = (a, "b", );
                emptyList = ();
                nested = { inner = value; };
                raw = <01 23 ab CD>;
            }
            """#
        let parsedSample = try parseOpenStepPlist(Data(samplePlist.utf8))
        try expect(
            parsedSample
                == .dictionary([
                    "unquoted": .string("foo_bar$1/2:3.4-5"),
                    "quoted": .string("line1\n\t\"quote\"\\slashA\u{1F600}A"),
                    "list": .array([.string("a"), .string("b")]),
                    "emptyList": .array([]),
                    "nested": .dictionary(["inner": .string("value")]),
                    "raw": .data(Data([0x01, 0x23, 0xAB, 0xCD])),
                ]), "parse OpenStep ASCII plist syntax")
        do {
            _ = try parseOpenStepPlist(Data("{ broken = (1, 2; }".utf8))
            throw ArchitectureError("Malformed plist did not fail")
        } catch {
            try expect(
                !String(describing: error).contains("did not fail"),
                "reject malformed OpenStep plist")
        }

        let octalSample = Data("{ a = \"\\351\"; b = \"\\200\\375\"; }".utf8)
        try expect(
            try parseOpenStepPlist(octalSample)
                == .dictionary(["a": .string("Ø"), "b": .string("\u{00A0}ÿ")]),
            "decode non-ASCII octal escapes with legacy NeXTSTEP encoding")
        do {
            _ = try parseOpenStepPlist(Data("{ bad = \"\\376\"; }".utf8))
            throw ArchitectureError("Invalid NeXTSTEP octal escape did not fail")
        } catch {
            try expect(
                !String(describing: error).contains("did not fail"),
                "reject invalid NeXTSTEP octal escape \\376")
        }

        #if os(macOS) && !TEST_LINUX_COMPAT
            func fromJSONObject(_ object: Any) throws -> OpenStepPlistValue {
                if let text = object as? String {
                    return .string(text)
                }
                if let array = object as? [Any] {
                    return .array(try array.map(fromJSONObject))
                }
                if let dict = object as? [String: Any] {
                    var result: [String: OpenStepPlistValue] = [:]
                    result.reserveCapacity(dict.count)
                    for (key, val) in dict {
                        result[key] = try fromJSONObject(val)
                    }
                    return .dictionary(result)
                }
                throw ArchitectureError("Unexpected JSON type from plutil: \(type(of: object))")
            }
            let rawPbxproj = try Data(contentsOf: root.appending(path: projectPath))
            let pureSwiftPlist = try parseOpenStepPlist(rawPbxproj)
            let plutilJSON = try JSONSerialization.jsonObject(
                with: command(root, "plutil", ["-convert", "json", "-o", "-", projectPath]))
            let plutilPlist = try fromJSONObject(plutilJSON)
            try expect(
                pureSwiftPlist == plutilPlist,
                "pure-Swift OpenStep plist parser matches plutil on real project.pbxproj")

            let nonASCIIFixtureURL = FileManager.default.temporaryDirectory
                .appending(path: "clinical-arch-non-ascii-\(UUID().uuidString).plist")
            defer { try? FileManager.default.removeItem(at: nonASCIIFixtureURL) }
            let nonASCIIFixture = Data(
                "{ oct = \"\\200\\351\\375\"; uni = \"\\U00E9\\UD83D\\UDE00\"; utf8 = \"café Ø\"; }\n"
                    .utf8
            )
            try nonASCIIFixture.write(to: nonASCIIFixtureURL)
            let nonASCIIPure = try parseOpenStepPlist(nonASCIIFixture)
            let nonASCIIPlutilJSON = try JSONSerialization.jsonObject(
                with: command(
                    root, "plutil", ["-convert", "json", "-o", "-", nonASCIIFixtureURL.path]))
            try expect(
                nonASCIIPure == (try fromJSONObject(nonASCIIPlutilJSON)),
                "pure-Swift parser matches plutil on non-ASCII octal and Unicode escapes")
        #endif

        func quotePlistString(_ text: String) -> String {
            let escaped =
                text
                .replacing("\\", with: "\\\\")
                .replacing("\"", with: "\\\"")
                .replacing("\n", with: "\\n")
                .replacing("\t", with: "\\t")
            return "\"\(escaped)\""
        }
        func encodePlistProject(_ project: XcodeProject) -> Data {
            func field(_ key: String, _ value: String?) -> String? {
                value.map { "\t\t\t\(key) = \(quotePlistString($0));" }
            }
            func arrayField(_ key: String, _ values: [String]?) -> String? {
                values.map { list in
                    let items = list.map(quotePlistString).joined(separator: ", ")
                    return "\t\t\t\(key) = (\(items));"
                }
            }
            var lines = [
                "// !$*UTF8*$!",
                "{",
                "\tobjects = {",
            ]
            for id in project.objects.keys.sorted() {
                let obj = project.objects[id]!
                lines.append("\t\t\(quotePlistString(id)) = {")
                let entries = [
                    field("isa", obj.isa),
                    field("mainGroup", obj.mainGroup),
                    field("sourceTree", obj.sourceTree),
                    field("path", obj.path),
                    arrayField("children", obj.children),
                    field("name", obj.name),
                    arrayField("packageProductDependencies", obj.packageProductDependencies),
                    arrayField("buildPhases", obj.buildPhases),
                    arrayField("files", obj.files),
                    field("productRef", obj.productRef),
                    field("fileRef", obj.fileRef),
                    arrayField("fileSystemSynchronizedGroups", obj.fileSystemSynchronizedGroups),
                    arrayField("exceptions", obj.exceptions),
                    field("target", obj.target),
                    arrayField("membershipExceptions", obj.membershipExceptions),
                    arrayField("dependencies", obj.dependencies),
                    field("productName", obj.productName),
                ].compactMap { $0 }
                lines.append(contentsOf: entries)
                lines.append("\t\t};")
            }
            lines.append("\t};")
            lines.append("\trootObject = \(quotePlistString(project.rootObject));")
            lines.append("}")
            return Data(lines.joined(separator: "\n").utf8)
        }

        let project = try loadXcodeProject(at: root.appending(path: projectPath))
        let widget = project.objects.first {
            $0.value.name == "ClinicalWidgetExtension" && $0.value.isa == "PBXNativeTarget"
        }!.key
        let persistence = project.objects.first {
            $0.value.productName == "ClinicalPersistence"
        }!.key
        var brokenProject = project
        brokenProject.objects[widget]?.packageProductDependencies?.append(persistence)
        try expect(
            try checkProject(brokenProject, paths: ["ClinicalShared/New.swift"]).failures
                .contains { $0.contains("model-only") }, "reject widget persistence product")
        try expect(
            try checkProject(project, paths: ["ClinicalShared/New.swift"]).widgetSources
                .contains("ClinicalShared/New.swift"), "synchronized shared membership")
        let originalProject = try Data(contentsOf: fixture.appending(path: projectPath))
        try encodePlistProject(brokenProject).write(
            to: fixture.appending(path: projectPath))
        try stage()
        try originalProject.write(to: fixture.appending(path: projectPath))
        try expect(
            try checkArchitecture(root: fixture, staged: true).contains {
                $0.contains("model-only")
            }, "read project from index")
        try stage()
        try FileManager.default.removeItem(at: fixture.appending(path: projectPath))
        do {
            _ = try checkArchitecture(root: fixture, staged: false)
            throw ArchitectureError("Missing project did not fail")
        } catch {
            try expect(
                !String(describing: error).contains("did not fail"),
                "missing project check fails clearly")
        }
        print("Passed \(count) architecture checks.")
    }
}
