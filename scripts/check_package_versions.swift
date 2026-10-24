import Foundation

struct PackageVersionError: Error, CustomStringConvertible {
    let description: String
}

struct ResolvedPackages: Decodable {
    struct Pin: Decodable {
        struct State: Decodable, Equatable, CustomStringConvertible {
            let version: String?
            let revision: String
            var description: String { "version=\(version ?? "none"), revision=\(revision)" }
        }
        let identity: String
        let state: State
    }
    let pins: [Pin]
}

func readPins(_ path: String) throws -> [String: ResolvedPackages.Pin.State] {
    do {
        let file = try JSONDecoder().decode(
            ResolvedPackages.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        var pins: [String: ResolvedPackages.Pin.State] = [:]
        for pin in file.pins {
            guard pins.updateValue(pin.state, forKey: pin.identity) == nil else {
                throw PackageVersionError(
                    description: "Duplicate package identity: \(pin.identity)")
            }
        }
        return pins
    } catch {
        throw PackageVersionError(description: "Cannot read or decode \(path): \(error)")
    }
}

do {
    let package = try readPins("Package.resolved")
    let app = try readPins(
        "clinical-swift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    let shared = Set(package.keys).intersection(app.keys).sorted()
    var aligned = true
    for identity in shared {
        if let packageState = package[identity], let appState = app[identity],
            packageState != appState
        {
            aligned = false
            print("\(identity): Package.resolved: \(packageState)")
            print("\(identity): Xcode Package.resolved: \(appState)")
        }
    }
    guard aligned else { exit(1) }
    print("Package versions and revisions match for \(shared.count) shared dependencies.")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
