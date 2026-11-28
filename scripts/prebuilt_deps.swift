import CryptoKit
import Darwin
import Foundation

struct PrebuiltDepsError: Error, CustomStringConvertible {
    let description: String
}

enum PrebuiltModules {
    static let schemaVersion = "v2"

    // Prebuild third-party SPM modules only; ClinicalModels and ClinicalPersistence compile natively.
    static let thirdParty: [String] = [
        "Clocks",
        "CombineSchedulers",
        "ConcurrencyExtras",
        "CustomDump",
        "Dependencies",
        "GRDB",
        "IdentifiedCollections",
        "InternalCollectionsUtilities",
        "IssueReporting",
        "OrderedCollections",
        "Perception",
        "PerceptionCore",
        "SQLiteData",
        "Sharing",
        "Sharing1",
        "Sharing2",
        "StructuredQueries",
        "StructuredQueriesCore",
        "StructuredQueriesSQLite",
        "StructuredQueriesSQLiteCore",
    ]

    static let clinicalModelsDeps: Set<String> = [
        "Clocks",
        "CombineSchedulers",
        "ConcurrencyExtras",
        "CustomDump",
        "Dependencies",
        "IssueReporting",
        "PerceptionCore",
    ]

    static let widgetDeps: Set<String> = [
        "Clocks",
        "CombineSchedulers",
        "ConcurrencyExtras",
        "CustomDump",
        "Dependencies",
        "GRDB",
        "IssueReporting",
        "PerceptionCore",
    ]

    static let macros: [String] = [
        "PerceptionMacros",
        "StructuredQueriesMacros",
        "StructuredQueriesSQLiteMacros",
    ]

    static let resourceBundles: [String] = [
        "GRDB_GRDB.bundle",
        "swift-sharing_Sharing.bundle",
    ]
}

private enum LocalTargetIDs {
    static let modelsTarget = "F0A000000000000000000001"
    static let modelsProduct = "F0A000000000000000000002"
    static let modelsGroup = "F0A000000000000000000003"
    static let modelsSourcesPhase = "F0A000000000000000000004"
    static let modelsFrameworksPhase = "F0A000000000000000000005"
    static let modelsConfigList = "F0A000000000000000000006"
    static let modelsDebugConfig = "F0A000000000000000000007"
    static let modelsReleaseConfig = "F0A000000000000000000008"
    static let modelsProxy = "F0A000000000000000000009"
    static let modelsDependency = "F0A00000000000000000000A"
    static let modelsLinkInApp = "F0A00000000000000000000B"
    static let modelsLinkInWidget = "F0A00000000000000000000C"
    static let modelsLinkInPersistence = "F0A00000000000000000000D"

    static let persistenceTarget = "F0B000000000000000000001"
    static let persistenceProduct = "F0B000000000000000000002"
    static let persistenceGroup = "F0B000000000000000000003"
    static let persistenceSourcesPhase = "F0B000000000000000000004"
    static let persistenceFrameworksPhase = "F0B000000000000000000005"
    static let persistenceConfigList = "F0B000000000000000000006"
    static let persistenceDebugConfig = "F0B000000000000000000007"
    static let persistenceReleaseConfig = "F0B000000000000000000008"
    static let persistenceProxy = "F0B000000000000000000009"
    static let persistenceDependency = "F0B00000000000000000000A"
    static let persistenceLinkInApp = "F0B00000000000000000000B"
}

struct PrebuiltFingerprints: Equatable {
    let deps: String
    let project: String
}

struct PrebuiltEnsureRequest {
    let repoRoot: URL
    let derivedData: URL
    let outputDir: URL
    let simulatorID: String
    let developerDir: String
}

private func hexDigest(_ hasher: SHA256) -> String {
    hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func hashFileIfPresent(at url: URL, label: String, into hasher: inout SHA256) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    hasher.update(data: Data("FILE:\(label)\n".utf8))
    hasher.update(data: try Data(contentsOf: url))
    hasher.update(data: Data([0]))
}

func readXcodeVersion(developerDir: String) -> String? {
    let versionPlist = URL(fileURLWithPath: developerDir)
        .deletingLastPathComponent()
        .appendingPathComponent("version.plist")
    guard
        let data = try? Data(contentsOf: versionPlist),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any]
    else {
        return nil
    }
    let shortVersion = plist["CFBundleShortVersionString"] as? String ?? ""
    let buildVersion = plist["ProductBuildVersion"] as? String ?? ""
    guard !shortVersion.isEmpty || !buildVersion.isEmpty else { return nil }
    return "\(shortVersion)-\(buildVersion)"
}

func currentHostArch() -> String {
    #if arch(arm64)
        "arm64"
    #else
        "x86_64"
    #endif
}

func computeFingerprints(
    repoRoot: URL,
    xcodeVersion: String,
    arch: String = currentHostArch()
) throws -> PrebuiltFingerprints {
    var depsHasher = SHA256()
    depsHasher.update(data: Data("SCHEMA:\(PrebuiltModules.schemaVersion)\n".utf8))
    depsHasher.update(data: Data("XCODE:\(xcodeVersion)\n".utf8))
    depsHasher.update(data: Data("ARCH:\(arch)\n".utf8))
    depsHasher.update(
        data: Data("MODULES:\(PrebuiltModules.thirdParty.joined(separator: ","))\n".utf8)
    )
    depsHasher.update(
        data: Data("MACROS:\(PrebuiltModules.macros.joined(separator: ","))\n".utf8)
    )

    // Sources/ compiles natively in the generated project, so only package/Xcode changes bust deps.
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("Package.swift"),
        label: "Package.swift",
        into: &depsHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("Package.resolved"),
        label: "Package.resolved",
        into: &depsHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent(
            "clinical-swift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        ),
        label: "xcodeproj/Package.resolved",
        into: &depsHasher
    )

    let depsHash = hexDigest(depsHasher)

    var projectHasher = SHA256()
    projectHasher.update(data: Data("DEPS:\(depsHash)\n".utf8))
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent("clinical-swift.xcodeproj/project.pbxproj"),
        label: "project.pbxproj",
        into: &projectHasher
    )
    try hashFileIfPresent(
        at: repoRoot.appendingPathComponent(
            "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
        ),
        label: "clinical-swift.xcscheme",
        into: &projectHasher
    )

    return PrebuiltFingerprints(deps: depsHash, project: hexDigest(projectHasher))
}

private func makeObjectID(_ prefix: String, index: Int) -> String {
    String(format: "F0%@%018X", prefix, index)
}

private func regexReplace(
    in text: String,
    pattern: String,
    template: String,
    dotMatchesLineSeparators: Bool = false
) throws -> (result: String, count: Int) {
    var options: NSRegularExpression.Options = []
    if dotMatchesLineSeparators {
        options.insert(.dotMatchesLineSeparators)
    }
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.numberOfMatches(in: text, range: range)
    let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    return (result, matches)
}

private func insertAfterMarker(_ marker: String, content: String, in text: inout String) throws {
    guard let range = text.range(of: marker) else {
        throw PrebuiltDepsError(description: "Missing marker in project.pbxproj: \(marker)")
    }
    text.replaceSubrange(range, with: marker + content)
}

func rewriteProjectForPrebuilt(
    canonicalPBXProj: String,
    outputRelativePath: String,
    projectDirPath: String,
    resourceBundles: [String]
) throws -> String {
    var text = canonicalPBXProj

    for section in [
        "XCLocalSwiftPackageReference",
        "XCRemoteSwiftPackageReference",
        "XCSwiftPackageProductDependency",
    ] {
        text =
            try regexReplace(
                in: text,
                pattern: #"\n/\* Begin "# + section + #" section \*/.*?/\* End "# + section
                    + #" section \*/\n"#,
                template: "\n",
                dotMatchesLineSeparators: true
            ).result
    }

    text =
        try regexReplace(
            in: text,
            pattern: #"\t\t\tpackageReferences = \(\n.*?\t\t\t\);\n"#,
            template: "",
            dotMatchesLineSeparators: true
        ).result

    text =
        try regexReplace(
            in: text,
            pattern: #"\t\t\tpackageProductDependencies = \(\n.*?\t\t\t\);\n"#,
            template: "\t\t\tpackageProductDependencies = (\n\t\t\t);\n",
            dotMatchesLineSeparators: true
        ).result

    text =
        try regexReplace(
            in: text,
            pattern:
                #"\t\t[0-9A-F]+ /\* .* in Frameworks \*/ = \{isa = PBXBuildFile; (?:productRef = .*?; )?\};\n"#,
            template: ""
        ).result

    // Point the generated project back to the repository root so relative source/plist paths resolve.
    let projectDirReplacement = try regexReplace(
        in: text,
        pattern: #"\t\t\tprojectDirPath = "";\n\t\t\tprojectRoot = "";\n"#,
        template:
            "\t\t\tprojectDirPath = \"\(projectDirPath)\";\n\t\t\tprojectRoot = \"\(projectDirPath)\";\n"
    )
    guard projectDirReplacement.count == 1 else {
        throw PrebuiltDepsError(
            description: "Could not locate projectDirPath/projectRoot in project.pbxproj."
        )
    }
    text = projectDirReplacement.result

    var fileRefs: [String] = [
        "\t\t\(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */ = {isa = PBXFileReference; explicitFileType = archive.ar; includeInIndex = 0; path = libClinicalModels.a; sourceTree = BUILT_PRODUCTS_DIR; };",
        "\t\t\(LocalTargetIDs.persistenceProduct) /* libClinicalPersistence.a */ = {isa = PBXFileReference; explicitFileType = archive.ar; includeInIndex = 0; path = libClinicalPersistence.a; sourceTree = BUILT_PRODUCTS_DIR; };",
    ]
    var buildFiles: [String] = [
        "\t\t\(LocalTargetIDs.modelsLinkInApp) /* libClinicalModels.a in Frameworks */ = {isa = PBXBuildFile; fileRef = \(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */; };",
        "\t\t\(LocalTargetIDs.persistenceLinkInApp) /* libClinicalPersistence.a in Frameworks */ = {isa = PBXBuildFile; fileRef = \(LocalTargetIDs.persistenceProduct) /* libClinicalPersistence.a */; };",
        "\t\t\(LocalTargetIDs.modelsLinkInWidget) /* libClinicalModels.a in Frameworks */ = {isa = PBXBuildFile; fileRef = \(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */; };",
        "\t\t\(LocalTargetIDs.modelsLinkInPersistence) /* libClinicalModels.a in Frameworks */ = {isa = PBXBuildFile; fileRef = \(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */; };",
    ]

    var appFrameworkEntries: [String] = [
        "\t\t\t\t\(LocalTargetIDs.modelsLinkInApp) /* libClinicalModels.a in Frameworks */,",
        "\t\t\t\t\(LocalTargetIDs.persistenceLinkInApp) /* libClinicalPersistence.a in Frameworks */,",
    ]
    var widgetFrameworkEntries: [String] = [
        "\t\t\t\t\(LocalTargetIDs.modelsLinkInWidget) /* libClinicalModels.a in Frameworks */,"
    ]
    var modelsFrameworkEntries: [String] = []
    var persistenceFrameworkEntries: [String] = [
        "\t\t\t\t\(LocalTargetIDs.modelsLinkInPersistence) /* libClinicalModels.a in Frameworks */,"
    ]
    var appResourceEntries: [String] = []

    for (offset, mod) in PrebuiltModules.thirdParty.enumerated() {
        let idx = offset + 1
        let fref = makeObjectID("0100", index: idx)
        let appBuild = makeObjectID("0200", index: idx)
        let persistenceBuild = makeObjectID("0700", index: idx)
        fileRefs.append(
            "\t\t\(fref) /* \(mod).xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = \(mod).xcframework; path = \(outputRelativePath)/XCFrameworks/\(mod).xcframework; sourceTree = SOURCE_ROOT; };"
        )
        buildFiles.append(
            "\t\t\(appBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
        )
        appFrameworkEntries.append("\t\t\t\t\(appBuild) /* \(mod).xcframework in Frameworks */,")

        buildFiles.append(
            "\t\t\(persistenceBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
        )
        persistenceFrameworkEntries.append(
            "\t\t\t\t\(persistenceBuild) /* \(mod).xcframework in Frameworks */,"
        )

        if PrebuiltModules.widgetDeps.contains(mod) {
            let widgetBuild = makeObjectID("0300", index: idx)
            buildFiles.append(
                "\t\t\(widgetBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
            )
            widgetFrameworkEntries.append(
                "\t\t\t\t\(widgetBuild) /* \(mod).xcframework in Frameworks */,"
            )
        }

        if PrebuiltModules.clinicalModelsDeps.contains(mod) {
            let modelsBuild = makeObjectID("0600", index: idx)
            buildFiles.append(
                "\t\t\(modelsBuild) /* \(mod).xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(mod).xcframework */; };"
            )
            modelsFrameworkEntries.append(
                "\t\t\t\t\(modelsBuild) /* \(mod).xcframework in Frameworks */,"
            )
        }
    }

    for (offset, bundle) in resourceBundles.enumerated() {
        let idx = offset + 1
        let fref = makeObjectID("0400", index: idx)
        let resBuild = makeObjectID("0500", index: idx)
        fileRefs.append(
            "\t\t\(fref) /* \(bundle) */ = {isa = PBXFileReference; lastKnownFileType = wrapper.cfbundle; name = \(bundle); path = \(outputRelativePath)/Resources/\(bundle); sourceTree = SOURCE_ROOT; };"
        )
        buildFiles.append(
            "\t\t\(resBuild) /* \(bundle) in Resources */ = {isa = PBXBuildFile; fileRef = \(fref) /* \(bundle) */; };"
        )
        appResourceEntries.append("\t\t\t\t\(resBuild) /* \(bundle) in Resources */,")
    }

    try insertAfterMarker(
        "/* Begin PBXBuildFile section */\n",
        content: buildFiles.joined(separator: "\n") + "\n",
        in: &text
    )
    try insertAfterMarker(
        "/* Begin PBXFileReference section */\n",
        content: fileRefs.joined(separator: "\n") + "\n",
        in: &text
    )

    let syncGroups = """
        		\(LocalTargetIDs.modelsGroup) /* ClinicalModels */ = {
        			isa = PBXFileSystemSynchronizedRootGroup;
        			path = Sources/ClinicalModels;
        			sourceTree = "<group>";
        		};
        		\(LocalTargetIDs.persistenceGroup) /* ClinicalPersistence */ = {
        			isa = PBXFileSystemSynchronizedRootGroup;
        			path = Sources/ClinicalPersistence;
        			sourceTree = "<group>";
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXFileSystemSynchronizedRootGroup section */\n",
        content: syncGroups,
        in: &text
    )

    let proxies = """
        		\(LocalTargetIDs.modelsProxy) /* PBXContainerItemProxy */ = {
        			isa = PBXContainerItemProxy;
        			containerPortal = 79438C3B2FD2D07100C0E6EF /* Project object */;
        			proxyType = 1;
        			remoteGlobalIDString = \(LocalTargetIDs.modelsTarget);
        			remoteInfo = ClinicalModels;
        		};
        		\(LocalTargetIDs.persistenceProxy) /* PBXContainerItemProxy */ = {
        			isa = PBXContainerItemProxy;
        			containerPortal = 79438C3B2FD2D07100C0E6EF /* Project object */;
        			proxyType = 1;
        			remoteGlobalIDString = \(LocalTargetIDs.persistenceTarget);
        			remoteInfo = ClinicalPersistence;
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXContainerItemProxy section */\n",
        content: proxies,
        in: &text
    )

    let targetDeps = """
        		\(LocalTargetIDs.modelsDependency) /* PBXTargetDependency */ = {
        			isa = PBXTargetDependency;
        			target = \(LocalTargetIDs.modelsTarget) /* ClinicalModels */;
        			targetProxy = \(LocalTargetIDs.modelsProxy) /* PBXContainerItemProxy */;
        		};
        		\(LocalTargetIDs.persistenceDependency) /* PBXTargetDependency */ = {
        			isa = PBXTargetDependency;
        			target = \(LocalTargetIDs.persistenceTarget) /* ClinicalPersistence */;
        			targetProxy = \(LocalTargetIDs.persistenceProxy) /* PBXContainerItemProxy */;
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXTargetDependency section */\n",
        content: targetDeps,
        in: &text
    )

    let localSourcesPhases = """
        		\(LocalTargetIDs.modelsSourcesPhase) /* Sources */ = {
        			isa = PBXSourcesBuildPhase;
        			buildActionMask = 2147483647;
        			files = (
        			);
        			runOnlyForDeploymentPostprocessing = 0;
        		};
        		\(LocalTargetIDs.persistenceSourcesPhase) /* Sources */ = {
        			isa = PBXSourcesBuildPhase;
        			buildActionMask = 2147483647;
        			files = (
        			);
        			runOnlyForDeploymentPostprocessing = 0;
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXSourcesBuildPhase section */\n",
        content: localSourcesPhases,
        in: &text
    )

    let localFrameworksPhases = """
        		\(LocalTargetIDs.modelsFrameworksPhase) /* Frameworks */ = {
        			isa = PBXFrameworksBuildPhase;
        			buildActionMask = 2147483647;
        			files = (
        \(modelsFrameworkEntries.joined(separator: "\n"))
        			);
        			runOnlyForDeploymentPostprocessing = 0;
        		};
        		\(LocalTargetIDs.persistenceFrameworksPhase) /* Frameworks */ = {
        			isa = PBXFrameworksBuildPhase;
        			buildActionMask = 2147483647;
        			files = (
        \(persistenceFrameworkEntries.joined(separator: "\n"))
        			);
        			runOnlyForDeploymentPostprocessing = 0;
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXFrameworksBuildPhase section */\n",
        content: localFrameworksPhases,
        in: &text
    )

    let macroFlagEntries = PrebuiltModules.macros.flatMap { macro in
        [
            "\t\t\t\t\t\"-Xfrontend\",",
            "\t\t\t\t\t\"-load-plugin-executable\",",
            "\t\t\t\t\t\"-Xfrontend\",",
            "\t\t\t\t\t\"$(PROJECT_DIR)/\(outputRelativePath)/Macros/\(macro)#\(macro)\",",
        ]
    }.joined(separator: "\n")

    // Mirror Package.swift settings: Swift 6 with nonisolated default isolation and macro plugins for Persistence.
    func localTargetConfigs(
        debugID: String,
        releaseID: String,
        moduleName: String,
        extraSwiftFlags: String?,
        extensionSafe: Bool
    ) -> String {
        func oneConfig(id: String, name: String) -> String {
            let extLine = extensionSafe ? "\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;\n" : ""
            let swiftFlagsBlock =
                extraSwiftFlags.map {
                    """
                    				OTHER_SWIFT_FLAGS = (
                    					"$(inherited)",
                    \($0)
                    				);

                    """
                } ?? ""
            return """
                		\(id) /* \(name) */ = {
                			isa = XCBuildConfiguration;
                			buildSettings = {
                \(extLine)				CODE_SIGN_STYLE = Automatic;
                				ENABLE_PREVIEWS = NO;
                				IPHONEOS_DEPLOYMENT_TARGET = 27.0;
                \(swiftFlagsBlock)				PRODUCT_MODULE_NAME = \(moduleName);
                				PRODUCT_NAME = \(moduleName);
                				SKIP_INSTALL = YES;
                				SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated;
                				SWIFT_EMIT_LOC_STRINGS = NO;
                				SWIFT_VERSION = 6.0;
                				TARGETED_DEVICE_FAMILY = "1,2";
                			};
                			name = \(name);
                		};

                """
        }
        return oneConfig(id: debugID, name: "Debug") + oneConfig(id: releaseID, name: "Release")
    }

    let persistenceSwiftFlags = """
        					"-Xcc",
        					"-fmodule-map-file=$(PROJECT_DIR)/\(outputRelativePath)/GRDBSQLite/module.modulemap",
        \(macroFlagEntries)
        """

    let localBuildConfigs =
        localTargetConfigs(
            debugID: LocalTargetIDs.modelsDebugConfig,
            releaseID: LocalTargetIDs.modelsReleaseConfig,
            moduleName: "ClinicalModels",
            extraSwiftFlags: nil,
            extensionSafe: true
        )
        + localTargetConfigs(
            debugID: LocalTargetIDs.persistenceDebugConfig,
            releaseID: LocalTargetIDs.persistenceReleaseConfig,
            moduleName: "ClinicalPersistence",
            extraSwiftFlags: persistenceSwiftFlags,
            extensionSafe: false
        )
    try insertAfterMarker(
        "/* Begin XCBuildConfiguration section */\n",
        content: localBuildConfigs,
        in: &text
    )

    let localConfigLists = """
        		\(LocalTargetIDs.modelsConfigList) /* Build configuration list for PBXNativeTarget "ClinicalModels" */ = {
        			isa = XCConfigurationList;
        			buildConfigurations = (
        				\(LocalTargetIDs.modelsDebugConfig) /* Debug */,
        				\(LocalTargetIDs.modelsReleaseConfig) /* Release */,
        			);
        			defaultConfigurationIsVisible = 0;
        			defaultConfigurationName = Release;
        		};
        		\(LocalTargetIDs.persistenceConfigList) /* Build configuration list for PBXNativeTarget "ClinicalPersistence" */ = {
        			isa = XCConfigurationList;
        			buildConfigurations = (
        				\(LocalTargetIDs.persistenceDebugConfig) /* Debug */,
        				\(LocalTargetIDs.persistenceReleaseConfig) /* Release */,
        			);
        			defaultConfigurationIsVisible = 0;
        			defaultConfigurationName = Release;
        		};

        """
    try insertAfterMarker(
        "/* Begin XCConfigurationList section */\n",
        content: localConfigLists,
        in: &text
    )

    let localNativeTargets = """
        		\(LocalTargetIDs.modelsTarget) /* ClinicalModels */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = \(LocalTargetIDs.modelsConfigList) /* Build configuration list for PBXNativeTarget "ClinicalModels" */;
        			buildPhases = (
        				\(LocalTargetIDs.modelsSourcesPhase) /* Sources */,
        				\(LocalTargetIDs.modelsFrameworksPhase) /* Frameworks */,
        			);
        			buildRules = (
        			);
        			dependencies = (
        			);
        			fileSystemSynchronizedGroups = (
        				\(LocalTargetIDs.modelsGroup) /* ClinicalModels */,
        			);
        			name = ClinicalModels;
        			packageProductDependencies = (
        			);
        			productName = ClinicalModels;
        			productReference = \(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */;
        			productType = "com.apple.product-type.library.static";
        		};
        		\(LocalTargetIDs.persistenceTarget) /* ClinicalPersistence */ = {
        			isa = PBXNativeTarget;
        			buildConfigurationList = \(LocalTargetIDs.persistenceConfigList) /* Build configuration list for PBXNativeTarget "ClinicalPersistence" */;
        			buildPhases = (
        				\(LocalTargetIDs.persistenceSourcesPhase) /* Sources */,
        				\(LocalTargetIDs.persistenceFrameworksPhase) /* Frameworks */,
        			);
        			buildRules = (
        			);
        			dependencies = (
        				\(LocalTargetIDs.modelsDependency) /* PBXTargetDependency */,
        			);
        			fileSystemSynchronizedGroups = (
        				\(LocalTargetIDs.persistenceGroup) /* ClinicalPersistence */,
        			);
        			name = ClinicalPersistence;
        			packageProductDependencies = (
        			);
        			productName = ClinicalPersistence;
        			productReference = \(LocalTargetIDs.persistenceProduct) /* libClinicalPersistence.a */;
        			productType = "com.apple.product-type.library.static";
        		};

        """
    try insertAfterMarker(
        "/* Begin PBXNativeTarget section */\n",
        content: localNativeTargets,
        in: &text
    )

    // Register local targets in PBXProject.targets, mainGroup, and Products group.
    let projectTargets = try regexReplace(
        in: text,
        pattern: #"(targets = \(\n\t\t\t\t79438C422FD2D07100C0E6EF /\* clinical-swift \*/,\n)"#,
        template:
            "$1\t\t\t\t\(LocalTargetIDs.modelsTarget) /* ClinicalModels */,\n\t\t\t\t\(LocalTargetIDs.persistenceTarget) /* ClinicalPersistence */,\n"
    )
    guard projectTargets.count == 1 else {
        throw PrebuiltDepsError(description: "Could not add local targets to PBXProject.targets.")
    }
    text = projectTargets.result

    let mainGroupChildren = try regexReplace(
        in: text,
        pattern:
            #"(79438C3A2FD2D07100C0E6EF = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n\t\t\t\t79438C452FD2D07100C0E6EF /\* clinical-swift \*/,\n)"#,
        template:
            "$1\t\t\t\t\(LocalTargetIDs.modelsGroup) /* ClinicalModels */,\n\t\t\t\t\(LocalTargetIDs.persistenceGroup) /* ClinicalPersistence */,\n"
    )
    guard mainGroupChildren.count == 1 else {
        throw PrebuiltDepsError(description: "Could not add local groups to mainGroup.")
    }
    text = mainGroupChildren.result

    let productsChildren = try regexReplace(
        in: text,
        pattern:
            #"(79438C442FD2D07100C0E6EF /\* Products \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n\t\t\t\t79438C432FD2D07100C0E6EF /\* clinical-swift\.app \*/,\n)"#,
        template:
            "$1\t\t\t\t\(LocalTargetIDs.modelsProduct) /* libClinicalModels.a */,\n\t\t\t\t\(LocalTargetIDs.persistenceProduct) /* libClinicalPersistence.a */,\n"
    )
    guard productsChildren.count == 1 else {
        throw PrebuiltDepsError(description: "Could not add local products to Products group.")
    }
    text = productsChildren.result

    // Add target dependencies so Xcode builds ClinicalModels and ClinicalPersistence before app & widget.
    let appDeps = try regexReplace(
        in: text,
        pattern: #"(B2000000000000000000000E /\* PBXTargetDependency \*/,\n)"#,
        template:
            "$1\t\t\t\t\(LocalTargetIDs.modelsDependency) /* PBXTargetDependency */,\n\t\t\t\t\(LocalTargetIDs.persistenceDependency) /* PBXTargetDependency */,\n"
    )
    guard appDeps.count == 1 else {
        throw PrebuiltDepsError(description: "Could not add local dependencies to clinical-swift.")
    }
    text = appDeps.result

    let widgetDepsPatch = try regexReplace(
        in: text,
        pattern:
            #"(B20000000000000000000004 /\* ClinicalWidgetExtension \*/ = \{.*?dependencies = \(\n)(\t\t\t\);\n)"#,
        template: "$1\t\t\t\t\(LocalTargetIDs.modelsDependency) /* PBXTargetDependency */,\n$2",
        dotMatchesLineSeparators: true
    )
    guard widgetDepsPatch.count == 1 else {
        throw PrebuiltDepsError(
            description: "Could not add ClinicalModels dependency to ClinicalWidgetExtension."
        )
    }
    text = widgetDepsPatch.result

    func replaceBuildPhase(
        phaseID: String,
        comment: String,
        isa: String,
        entries: [String]
    ) throws {
        let pattern =
            #"(\t\t"# + phaseID + #" /\* "# + comment + #" \*/ = \{\n\t\t\tisa = "# + isa
            + #";\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \(\n).*?(\t\t\t\);\n)"#
        let joined = entries.isEmpty ? "" : entries.joined(separator: "\n") + "\n"
        let replaced = try regexReplace(
            in: text,
            pattern: pattern,
            template: "$1" + NSRegularExpression.escapedTemplate(for: joined) + "$2",
            dotMatchesLineSeparators: true
        )
        guard replaced.count == 1 else {
            throw PrebuiltDepsError(description: "Could not patch \(isa) \(phaseID).")
        }
        text = replaced.result
    }

    try replaceBuildPhase(
        phaseID: "79438C402FD2D07100C0E6EF",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: appFrameworkEntries
    )
    try replaceBuildPhase(
        phaseID: "B20000000000000000000006",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: widgetFrameworkEntries
    )
    try replaceBuildPhase(
        phaseID: "8BE2A0132FE0000000000005",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: []
    )
    try replaceBuildPhase(
        phaseID: "D30000000000000000000003",
        comment: "Frameworks",
        isa: "PBXFrameworksBuildPhase",
        entries: []
    )
    if !appResourceEntries.isEmpty {
        try replaceBuildPhase(
            phaseID: "79438C412FD2D07100C0E6EF",
            comment: "Resources",
            isa: "PBXResourcesBuildPhase",
            entries: appResourceEntries
        )
    }

    let extraSettings = """
        				OTHER_LDFLAGS = (
        					"$(inherited)",
        					"-lsqlite3",
        					"-lz",
        				);
        				OTHER_SWIFT_FLAGS = (
        					"$(inherited)",
        					"-Xcc",
        					"-fmodule-map-file=$(PROJECT_DIR)/\(outputRelativePath)/GRDBSQLite/module.modulemap",
        				);

        """
    let escapedExtra = NSRegularExpression.escapedTemplate(for: extraSettings)
    for cfgID in ["79438C512FD2D07300C0E6EF", "B20000000000000000000009"] {
        let pattern =
            #"(\t\t"# + cfgID
            + #" /\* Debug \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{\n)"#
        let replaced = try regexReplace(
            in: text,
            pattern: pattern,
            template: "$1" + escapedExtra
        )
        guard replaced.count == 1 else {
            throw PrebuiltDepsError(description: "Could not patch Debug configuration \(cfgID).")
        }
        text = replaced.result
    }

    return text
}

func rewriteSchemeForPrebuilt(_ canonicalScheme: String, prebuiltProjectRelativePath: String)
    -> String
{
    // Xcode resolves container: paths relative to projectDirPath (the repo root).
    canonicalScheme.replacingOccurrences(
        of: "container:clinical-swift.xcodeproj",
        with: "container:\(prebuiltProjectRelativePath)"
    )
}

private func runProcess(
    executable: String,
    arguments: [String],
    currentDirectory: URL? = nil,
    environment: [String: String]? = nil,
    captureOutput: Bool = true
) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    if let environment {
        process.environment = environment
    }
    process.standardInput = FileHandle.nullDevice

    if captureOutput {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errText = String(decoding: errData, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let outText = String(decoding: outData, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let detail = errText.isEmpty ? outText : errText
            throw PrebuiltDepsError(
                description: "\(executable) \(arguments.joined(separator: " ")) failed: \(detail)"
            )
        }
        return String(decoding: outData, as: UTF8.self)
    } else {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PrebuiltDepsError(
                description:
                    "\(executable) \(arguments.joined(separator: " ")) exited with status \(process.terminationStatus)."
            )
        }
        return ""
    }
}

private func frameworkInfoPlist(moduleName: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>\(moduleName)</string>
      <key>CFBundleIdentifier</key>
      <string>in.bitehaus.prebuilt.\(moduleName)</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>\(moduleName)</string>
      <key>CFBundlePackageType</key>
      <string>FMWK</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>MinimumOSVersion</key>
      <string>27.0</string>
      <key>CFBundleSupportedPlatforms</key>
      <array>
        <string>iPhoneSimulator</string>
      </array>
    </dict>
    </plist>
    """
}

func writeAtomically(_ text: String, to url: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let tmp = url.appendingPathExtension(
        "tmp.\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString)"
    )
    try Data(text.utf8).write(to: tmp)
    // Use POSIX rename(2) for atomic replacement so concurrent readers never see a missing file.
    guard Darwin.rename(tmp.path, url.path) == 0 else {
        let code = errno
        try? fm.removeItem(at: tmp)
        throw PrebuiltDepsError(
            description:
                "Failed to atomically replace \(url.path): \(String(cString: strerror(code)))"
        )
    }
}

private func withExclusiveLock<T>(at lockURL: URL, _ body: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(
        at: lockURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    // O_EXLOCK acquires an exclusive advisory lock atomically on open and releases it on close.
    let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_EXLOCK, 0o644)
    guard fd >= 0 else {
        let code = errno
        throw PrebuiltDepsError(
            description:
                "Failed to acquire lock \(lockURL.path): \(String(cString: strerror(code)))"
        )
    }
    defer { Darwin.close(fd) }
    return try body()
}

func canonicalWarmMakeEnvironment(
    baseEnvironment: [String: String],
    developerDir: String
) -> [String: String] {
    var env = baseEnvironment
    // Drop inherited Make overrides so caller SIMULATOR_NAME or EXTRA_BUILD_FLAGS cannot conflict or poison the cache.
    for key in ["MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES", "MAKELEVEL"] {
        env.removeValue(forKey: key)
    }
    env["DEVELOPER_DIR"] = developerDir
    return env
}

func canonicalWarmMakeArguments(request: PrebuiltEnsureRequest) -> [String] {
    [
        "--no-print-directory",
        "build",
        "PREBUILT=0",
        "CONFIGURATION=Debug",
        "SIMULATOR_ID=\(request.simulatorID)",
        "SIMULATOR_NAME=",
        "EXTRA_BUILD_FLAGS=",
        "XCODE_DEVELOPER_DIR=\(request.developerDir)",
        "DERIVED_DATA=\(request.derivedData.path)",
    ]
}

private func isDepsCacheValid(outputDir: URL, expectedFingerprint: String) -> Bool {
    let fm = FileManager.default
    let stampURL = outputDir.appendingPathComponent("deps.fingerprint")
    guard
        let current = try? String(contentsOf: stampURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        current == expectedFingerprint
    else {
        return false
    }
    let moduleMap = outputDir.appendingPathComponent("GRDBSQLite/module.modulemap")
    let shimHeader = outputDir.appendingPathComponent("GRDBSQLite/shim.h")
    guard fm.fileExists(atPath: moduleMap.path), fm.fileExists(atPath: shimHeader.path) else {
        return false
    }
    for mod in PrebuiltModules.thirdParty {
        let plist = outputDir.appendingPathComponent("XCFrameworks/\(mod).xcframework/Info.plist")
        if !fm.fileExists(atPath: plist.path) {
            return false
        }
    }
    for macro in PrebuiltModules.macros {
        let bin = outputDir.appendingPathComponent("Macros/\(macro)")
        if !fm.isExecutableFile(atPath: bin.path) {
            return false
        }
    }
    return true
}

private func isProjectCacheValid(outputDir: URL, expectedFingerprint: String) -> Bool {
    let fm = FileManager.default
    let stampURL = outputDir.appendingPathComponent("project.fingerprint")
    guard
        let current = try? String(contentsOf: stampURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        current == expectedFingerprint
    else {
        return false
    }
    let pbx = outputDir.appendingPathComponent("clinical-swift-prebuilt.xcodeproj/project.pbxproj")
    let scheme = outputDir.appendingPathComponent(
        "clinical-swift-prebuilt.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
    )
    return fm.fileExists(atPath: pbx.path) && fm.fileExists(atPath: scheme.path)
}

private func relativePath(from base: URL, to target: URL) -> String {
    let baseComponents = base.standardizedFileURL.pathComponents
    let targetComponents = target.standardizedFileURL.pathComponents
    var common = 0
    while common < min(baseComponents.count, targetComponents.count)
        && baseComponents[common] == targetComponents[common]
    {
        common += 1
    }
    let up = Array(repeating: "..", count: baseComponents.count - common)
    let down = Array(targetComponents.dropFirst(common))
    let combined = up + down
    return combined.isEmpty ? "." : combined.joined(separator: "/")
}

private func rebuildDepsCache(request: PrebuiltEnsureRequest, depsFingerprint: String) throws {
    let fm = FileManager.default
    let env = canonicalWarmMakeEnvironment(
        baseEnvironment: ProcessInfo.processInfo.environment,
        developerDir: request.developerDir
    )

    FileHandle.standardError.write(
        Data("[prebuilt] Refreshing canonical Debug simulator dependencies...\n".utf8)
    )
    _ = try runProcess(
        executable: "/usr/bin/make",
        arguments: canonicalWarmMakeArguments(request: request),
        currentDirectory: request.repoRoot,
        environment: env,
        captureOutput: false
    )

    let productsDir = request.derivedData.appendingPathComponent(
        "Build/Products/Debug-iphonesimulator"
    )
    let hostProductsDir = request.derivedData.appendingPathComponent("Build/Products/Debug")
    let grdbSQLiteSource = request.repoRoot.appendingPathComponent(
        "build/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"
    )
    guard fm.fileExists(atPath: grdbSQLiteSource.path) else {
        throw PrebuiltDepsError(
            description: "Missing GRDBSQLite checkout at \(grdbSQLiteSource.path)."
        )
    }

    let pid = ProcessInfo.processInfo.processIdentifier
    let stagingDir = request.outputDir.appendingPathComponent("staging.\(pid)")
    let xcfwTmpDir = request.outputDir.appendingPathComponent("XCFrameworks.tmp.\(pid)")
    let xcfwFinalDir = request.outputDir.appendingPathComponent("XCFrameworks")
    let macrosFinalDir = request.outputDir.appendingPathComponent("Macros")
    let grdbDestDir = request.outputDir.appendingPathComponent("GRDBSQLite")
    let resourcesDestDir = request.outputDir.appendingPathComponent("Resources")

    defer {
        try? fm.removeItem(at: stagingDir)
        try? fm.removeItem(at: xcfwTmpDir)
    }

    try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: xcfwTmpDir, withIntermediateDirectories: true)

    FileHandle.standardError.write(
        Data(
            "[prebuilt] Packaging \(PrebuiltModules.thirdParty.count) third-party XCFrameworks and \(PrebuiltModules.macros.count) macros...\n"
                .utf8
        )
    )

    let lock = NSLock()
    var firstError: Error?

    DispatchQueue.concurrentPerform(iterations: PrebuiltModules.thirdParty.count) { idx in
        lock.lock()
        let alreadyFailed = firstError != nil
        lock.unlock()
        if alreadyFailed { return }

        let mod = PrebuiltModules.thirdParty[idx]
        do {
            let objectFile = productsDir.appendingPathComponent("\(mod).o")
            let swiftModule = productsDir.appendingPathComponent("\(mod).swiftmodule")
            guard fm.fileExists(atPath: objectFile.path), fm.fileExists(atPath: swiftModule.path)
            else {
                throw PrebuiltDepsError(
                    description:
                        "Missing compiled module artifacts for \(mod) in \(productsDir.path)."
                )
            }

            let fwDir = stagingDir.appendingPathComponent("\(mod).framework")
            let modulesDir = fwDir.appendingPathComponent("Modules")
            try fm.createDirectory(at: modulesDir, withIntermediateDirectories: true)

            _ = try runProcess(
                executable: "/usr/bin/xcrun",
                arguments: [
                    "libtool", "-static",
                    "-o", fwDir.appendingPathComponent(mod).path,
                    objectFile.path,
                ],
                environment: env
            )
            try fm.copyItem(
                at: swiftModule,
                to: modulesDir.appendingPathComponent("\(mod).swiftmodule")
            )
            try Data(frameworkInfoPlist(moduleName: mod).utf8).write(
                to: fwDir.appendingPathComponent("Info.plist")
            )

            _ = try runProcess(
                executable: "/usr/bin/xcrun",
                arguments: [
                    "xcodebuild", "-create-xcframework",
                    "-allow-internal-distribution",
                    "-framework", fwDir.path,
                    "-output", xcfwTmpDir.appendingPathComponent("\(mod).xcframework").path,
                ],
                environment: env
            )
        } catch {
            lock.lock()
            if firstError == nil {
                firstError = error
            }
            lock.unlock()
        }
    }

    if let firstError {
        throw firstError
    }

    if fm.fileExists(atPath: xcfwFinalDir.path) {
        try fm.removeItem(at: xcfwFinalDir)
    }
    try fm.moveItem(at: xcfwTmpDir, to: xcfwFinalDir)

    if fm.fileExists(atPath: macrosFinalDir.path) {
        try fm.removeItem(at: macrosFinalDir)
    }
    try fm.createDirectory(at: macrosFinalDir, withIntermediateDirectories: true)
    for macro in PrebuiltModules.macros {
        let src = hostProductsDir.appendingPathComponent(macro)
        guard fm.isExecutableFile(atPath: src.path) else {
            throw PrebuiltDepsError(
                description:
                    "Missing compiled macro executable \(macro) in \(hostProductsDir.path)."
            )
        }
        try fm.copyItem(at: src, to: macrosFinalDir.appendingPathComponent(macro))
    }

    if fm.fileExists(atPath: grdbDestDir.path) {
        try fm.removeItem(at: grdbDestDir)
    }
    try fm.copyItem(at: grdbSQLiteSource, to: grdbDestDir)

    if fm.fileExists(atPath: resourcesDestDir.path) {
        try fm.removeItem(at: resourcesDestDir)
    }
    try fm.createDirectory(at: resourcesDestDir, withIntermediateDirectories: true)
    for bundle in PrebuiltModules.resourceBundles {
        let src = productsDir.appendingPathComponent(bundle)
        if fm.fileExists(atPath: src.path) {
            try fm.copyItem(at: src, to: resourcesDestDir.appendingPathComponent(bundle))
        }
    }

    try writeAtomically(
        depsFingerprint + "\n",
        to: request.outputDir.appendingPathComponent("deps.fingerprint")
    )
}

private func regeneratePrebuiltProject(request: PrebuiltEnsureRequest, projectFingerprint: String)
    throws
{
    let fm = FileManager.default
    let canonicalPBXURL = request.repoRoot.appendingPathComponent(
        "clinical-swift.xcodeproj/project.pbxproj"
    )
    let canonicalSchemeURL = request.repoRoot.appendingPathComponent(
        "clinical-swift.xcodeproj/xcshareddata/xcschemes/clinical-swift.xcscheme"
    )
    let canonicalPBX = try String(contentsOf: canonicalPBXURL, encoding: .utf8)
    let canonicalScheme = try String(contentsOf: canonicalSchemeURL, encoding: .utf8)

    let outputRel = relativePath(from: request.repoRoot, to: request.outputDir)
    let projectDirPath = relativePath(from: request.outputDir, to: request.repoRoot)
    let resourcesDir = request.outputDir.appendingPathComponent("Resources")
    let presentBundles = PrebuiltModules.resourceBundles.filter {
        fm.fileExists(atPath: resourcesDir.appendingPathComponent($0).path)
    }

    let rewrittenPBX = try rewriteProjectForPrebuilt(
        canonicalPBXProj: canonicalPBX,
        outputRelativePath: outputRel,
        projectDirPath: projectDirPath,
        resourceBundles: presentBundles
    )
    let rewrittenScheme = rewriteSchemeForPrebuilt(
        canonicalScheme,
        prebuiltProjectRelativePath: "\(outputRel)/clinical-swift-prebuilt.xcodeproj"
    )

    let prebuiltProjectURL = request.outputDir.appendingPathComponent(
        "clinical-swift-prebuilt.xcodeproj"
    )
    try writeAtomically(
        rewrittenPBX,
        to: prebuiltProjectURL.appendingPathComponent("project.pbxproj")
    )
    try writeAtomically(
        rewrittenScheme,
        to: prebuiltProjectURL.appendingPathComponent(
            "xcshareddata/xcschemes/clinical-swift.xcscheme"
        )
    )
    try writeAtomically(
        projectFingerprint + "\n",
        to: request.outputDir.appendingPathComponent("project.fingerprint")
    )
}

private func ensurePrebuilt(_ request: PrebuiltEnsureRequest) throws {
    let xcodeVersion: String
    if let plistVersion = readXcodeVersion(developerDir: request.developerDir) {
        xcodeVersion = plistVersion
    } else {
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = request.developerDir
        xcodeVersion = try runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["xcodebuild", "-version"],
            environment: env
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let fingerprints = try computeFingerprints(
        repoRoot: request.repoRoot,
        xcodeVersion: xcodeVersion
    )
    // Lock-free fast path when both caches already match.
    if isDepsCacheValid(outputDir: request.outputDir, expectedFingerprint: fingerprints.deps)
        && isProjectCacheValid(
            outputDir: request.outputDir,
            expectedFingerprint: fingerprints.project
        )
    {
        return
    }

    // Serialize stale refreshes across parallel builds and re-check after acquiring the lock.
    try withExclusiveLock(at: request.outputDir.appendingPathComponent(".lock")) {
        let depsValid = isDepsCacheValid(
            outputDir: request.outputDir,
            expectedFingerprint: fingerprints.deps
        )
        if !depsValid {
            try rebuildDepsCache(request: request, depsFingerprint: fingerprints.deps)
        }

        let projectValid =
            depsValid
            && isProjectCacheValid(
                outputDir: request.outputDir,
                expectedFingerprint: fingerprints.project
            )
        if !projectValid {
            try regeneratePrebuiltProject(
                request: request,
                projectFingerprint: fingerprints.project
            )
        }
    }
}

private func parseEnsureArguments(_ arguments: [String]) throws -> PrebuiltEnsureRequest {
    guard arguments.count >= 2, arguments[1] == "ensure" else {
        throw PrebuiltDepsError(
            description:
                "Usage: prebuilt_deps.swift ensure --repo-root PATH --derived-data PATH --output-dir PATH --simulator-id UDID [--developer-dir PATH]"
        )
    }
    var repoRoot = ""
    var derivedData = ""
    var outputDir = ""
    var simulatorID = ""
    var developerDir =
        ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
        ?? "/Applications/Xcode.app/Contents/Developer"

    var index = 2
    while index < arguments.count {
        let flag = arguments[index]
        guard index + 1 < arguments.count else {
            throw PrebuiltDepsError(description: "Missing value for \(flag).")
        }
        let value = arguments[index + 1]
        switch flag {
        case "--repo-root": repoRoot = value
        case "--derived-data": derivedData = value
        case "--output-dir": outputDir = value
        case "--simulator-id": simulatorID = value
        case "--developer-dir": developerDir = value
        default:
            throw PrebuiltDepsError(description: "Unknown option: \(flag).")
        }
        index += 2
    }

    guard !repoRoot.isEmpty, !derivedData.isEmpty, !outputDir.isEmpty, !simulatorID.isEmpty else {
        throw PrebuiltDepsError(
            description:
                "Required options: --repo-root, --derived-data, --output-dir, --simulator-id."
        )
    }

    return PrebuiltEnsureRequest(
        repoRoot: URL(fileURLWithPath: repoRoot),
        derivedData: URL(fileURLWithPath: derivedData),
        outputDir: URL(fileURLWithPath: outputDir),
        simulatorID: simulatorID,
        developerDir: developerDir
    )
}

private func runCLI() {
    do {
        let request = try parseEnsureArguments(CommandLine.arguments)
        try ensurePrebuilt(request)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

#if !SCRIPT_TESTS
    let _ = runCLI()
#endif
