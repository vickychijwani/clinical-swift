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
        var targets = graph["targets"] as! [[String: Any]]
        targets[0]["dependencies"] = [["byName": ["ClinicalPersistence", NSNull()]]]
        brokenGraph["targets"] = targets
        try expect(
            try checkPackage(brokenGraph).contains {
                $0.contains("ClinicalModels dependency ClinicalPersistence")
            }, "forbidden graph dependency without an import")
        targets[0]["path"] = "clinical-swift"
        brokenGraph["targets"] = targets
        try expect(
            try checkPackage(brokenGraph).contains { $0.contains("standard layout") },
            "custom source path")
        var productGraph = graph
        productGraph["products"] = [["name": "ClinicalModels", "targets": ["ClinicalPersistence"]]]
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
        #if os(macOS)
            let project = try jsonObject(
                command(root, "plutil", ["-convert", "json", "-o", "-", projectPath]))
            var objects = project["objects"] as! [String: [String: Any]]
            let widget = objects.first {
                $0.value["name"] as? String == "ClinicalWidgetExtension"
                    && $0.value["isa"] as? String == "PBXNativeTarget"
            }!.key
            let persistence = objects.first {
                $0.value["productName"] as? String == "ClinicalPersistence"
            }!.key
            var dependencies = objects[widget]!["packageProductDependencies"] as! [String]
            dependencies.append(persistence)
            objects[widget]!["packageProductDependencies"] = dependencies
            var brokenProject = project
            brokenProject["objects"] = objects
            try expect(
                try checkProject(brokenProject, paths: ["ClinicalShared/New.swift"]).failures
                    .contains { $0.contains("model-only") }, "reject widget persistence product")
            try expect(
                try checkProject(project, paths: ["ClinicalShared/New.swift"]).widgetSources
                    .contains("ClinicalShared/New.swift"), "synchronized shared membership")
            let originalProject = try Data(contentsOf: fixture.appending(path: projectPath))
            try JSONSerialization.data(withJSONObject: brokenProject).write(
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
                    "missing macOS project check fails clearly")
            }
        #endif
        print("Passed \(count) architecture checks.")
    }
}
