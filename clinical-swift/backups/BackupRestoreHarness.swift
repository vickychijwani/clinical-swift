#if INTERNAL_RECOVERY
    import Foundation

    /// Compile only in a signed internal build. No URL or distributed app invokes this entry point.
    @MainActor enum BackupRestoreHarness {
        static func run(restore: BackupRestore) throws {
            let arguments = CommandLine.arguments
            if arguments.contains("--restore-rollback") {
                try restore.rollBack()
            } else if arguments.contains("--restore-finalize") {
                try restore.finalize(confirmed: arguments.contains("--confirm-restore"))
            } else if let index = arguments.firstIndex(of: "--restore-import"),
                arguments.indices.contains(index + 1)
            {
                guard let datasetIndex = arguments.firstIndex(of: "--restore-dataset"),
                    arguments.indices.contains(datasetIndex + 1),
                    let datasetID = UUID(uuidString: arguments[datasetIndex + 1])
                else { throw BackupError.confirmationRequired }
                let source = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
                let staging = restore.store.directory.appending(path: "import-" + UUID().uuidString)
                try BackupFiles.createDirectory(staging)
                for name in ["snapshot.db", "snapshot.json"] {
                    try FileManager.default.copyItem(
                        at: source.appending(path: name), to: staging.appending(path: name))
                    try BackupFiles.protect(staging.appending(path: name))
                }
                let manifest = try BackupFiles.load(
                    BackupManifest.self, from: staging.appending(path: "snapshot.json"))
                try restore.prepare(
                    snapshot: BackupSnapshot(manifest: manifest, directory: staging),
                    expectedDatasetID: datasetID,
                    recoveryDate: .now,
                    confirmed: arguments.contains("--confirm-restore")
                )
                try restore.installOrResume()
            }
        }
    }
#endif
