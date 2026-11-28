import Foundation

struct DeviceScriptError: Error, CustomStringConvertible {
    let description: String
}

struct DevicectlOutput: Decodable {
    struct ResultPayload: Decodable {
        let devices: [CoreDevice]
    }

    let result: ResultPayload
}

struct CoreDevice: Decodable, Equatable {
    struct Properties: Decodable, Equatable {
        struct Hardware: Decodable, Equatable {
            let platform: String?
            let reality: String?
            let udid: String?
        }

        struct State: Decodable, Equatable {
            let name: String?
        }

        let hardware: Hardware?
        let state: State?
    }

    let identifier: String
    let properties: Properties?
    // Keep deprecated top-level fields as fallback for older Xcode devicectl JSON output.
    let hardwareProperties: Properties.Hardware?
    let deviceProperties: Properties.State?

    init(
        identifier: String,
        name: String?,
        udid: String?,
        platform: String? = "iOS",
        reality: String? = "physical"
    ) {
        self.identifier = identifier
        self.properties = Properties(
            hardware: Properties.Hardware(platform: platform, reality: reality, udid: udid),
            state: Properties.State(name: name)
        )
        self.hardwareProperties = nil
        self.deviceProperties = nil
    }

    var name: String? {
        properties?.state?.name ?? deviceProperties?.name
    }

    var udid: String? {
        properties?.hardware?.udid ?? hardwareProperties?.udid
    }

    var platform: String? {
        properties?.hardware?.platform ?? hardwareProperties?.platform
    }

    var reality: String? {
        properties?.hardware?.reality ?? hardwareProperties?.reality
    }
}

func resolvePhysicalIOSDeviceUDID(
    query: String,
    devices: [CoreDevice]
) throws -> String {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw DeviceScriptError(description: "DEVICE is required.")
    }

    let physicalIOSDevices = devices.filter { device in
        guard
            let udid = device.udid,
            !udid.isEmpty,
            device.reality?.caseInsensitiveCompare("physical") == .orderedSame,
            device.platform?.caseInsensitiveCompare("iOS") == .orderedSame
        else {
            return false
        }
        return true
    }

    let idMatches = physicalIOSDevices.filter { device in
        device.udid?.caseInsensitiveCompare(trimmed) == .orderedSame
            || device.identifier.caseInsensitiveCompare(trimmed) == .orderedSame
    }
    if idMatches.count == 1, let udid = idMatches[0].udid {
        return udid
    }

    let nameMatches = physicalIOSDevices.filter { $0.name == trimmed }
    if nameMatches.count == 1, let udid = nameMatches[0].udid {
        return udid
    }
    if nameMatches.count > 1 {
        let listing =
            nameMatches
            .compactMap { device in
                device.udid.map { "  - \(device.name ?? "Unknown") (\($0))" }
            }
            .sorted()
            .joined(separator: "\n")
        throw DeviceScriptError(
            description:
                "Multiple physical iOS devices are named \"\(trimmed)\":\n\(listing)\nPass DEVICE=\"<udid>\"."
        )
    }

    if physicalIOSDevices.isEmpty {
        throw DeviceScriptError(
            description: "No physical iOS device matching \"\(trimmed)\" was found."
        )
    }

    let listing =
        physicalIOSDevices
        .compactMap { device in
            device.udid.map { "  - \(device.name ?? "Unknown") (\($0))" }
        }
        .sorted()
        .joined(separator: "\n")
    throw DeviceScriptError(
        description:
            "Physical iOS device \"\(trimmed)\" was not found. Known physical iOS devices:\n\(listing)"
    )
}

private func listCoreDevices() throws -> [CoreDevice] {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("clinical-devicectl-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "devicectl", "list", "devices", "--json-output", tempURL.path,
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        throw DeviceScriptError(
            description: message.isEmpty ? "xcrun devicectl list devices failed." : message
        )
    }

    let data = try Data(contentsOf: tempURL)
    return try JSONDecoder().decode(DevicectlOutput.self, from: data).result.devices
}

private func runCLI() {
    do {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "resolve" else {
            throw DeviceScriptError(description: "Usage: device.swift resolve <name|udid>")
        }
        let devices = try listCoreDevices()
        let udid = try resolvePhysicalIOSDeviceUDID(
            query: CommandLine.arguments[2],
            devices: devices
        )
        print(udid)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

#if !SCRIPT_TESTS
    let _ = runCLI()
#endif
