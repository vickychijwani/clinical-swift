import CoreFoundation
import Foundation

// Require physical Release OAuth evidence for the configured Google client.
func checkBackupDevice(credentials: Data, configuration: Data) throws {
    struct InvalidEvidence: Error {}
    guard
        let plist = try PropertyListSerialization.propertyList(from: configuration, format: nil)
            as? [String: Any],
        let client = plist["GoogleBackupClientID"] as? String,
        let callback = plist["GoogleBackupCallbackScheme"] as? String,
        let record = try JSONSerialization.jsonObject(with: credentials) as? [String: Any],
        let device = record["deviceCheck"] as? [String: Any],
        let release = device["releaseOnDevice"] as? NSNumber,
        CFGetTypeID(release) == CFBooleanGetTypeID(), release.boolValue,
        device["clientID"] as? String == client,
        device["callbackScheme"] as? String == callback,
        record["clientID"] as? String == client
    else { throw InvalidEvidence() }
}

#if !SCRIPT_TESTS
    @main
    struct BackupDeviceCommand {
        static func main() {
            do {
                guard CommandLine.arguments.count == 2 else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .deletingLastPathComponent()
                try checkBackupDevice(
                    credentials: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
                    configuration: Data(
                        contentsOf: root.appending(path: "clinical-swift/Info.plist")))
            } catch {
                FileHandle.standardError.write(
                    Data(
                        "Release blocked: complete Google authorization in a signed Release internal build on a physical iPhone, then export its check credentials. Simulator credentials can run backup-drive-check.\n"
                            .utf8))
                exit(1)
            }
        }
    }
#endif
