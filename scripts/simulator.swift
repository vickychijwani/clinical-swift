import Foundation

private struct SimulatorScriptError: Error, CustomStringConvertible {
    let description: String
}

private struct DeviceList: Decodable {
    let devices: [String: [SimDevice]]
}

private struct SimDevice: Decodable, Equatable {
    let udid: String
    let name: String
    let state: String?
    let isAvailable: Bool?

    var available: Bool { isAvailable ?? true }
    var isBooted: Bool { state == "Booted" }
}

private struct RuntimeList: Decodable {
    let runtimes: [SimRuntime]
}

private struct SimRuntime: Decodable, Equatable {
    let identifier: String
    let version: String
    let isAvailable: Bool?
    let supportedDeviceTypes: [SimDeviceType]?

    var available: Bool { isAvailable ?? true }
}

private struct SimDeviceType: Decodable, Equatable {
    let name: String
    let identifier: String
}

private struct SimulatorRequest {
    let simulator: String
    let osVersion: String
    let name: String
    let explicitID: String
    let destination: String
}

private enum SimulatorMode: String {
    case resolve
    case ensure
}

private struct RuntimeDevice {
    let runtimeKey: String
    let device: SimDevice
}

private func isCISimulatorName(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.contains("ci simulator") || normalized.contains("clinical ci")
}

private func destinationFields(_ destination: String) -> [String: String] {
    var result: [String: String] = [:]
    for part in destination.split(separator: ",") {
        guard let separator = part.firstIndex(of: "=") else { continue }
        let key = part[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = part[part.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        result[key] = value
    }
    return result
}

private func runtimeSuffix(for osVersion: String) -> String {
    ".iOS-" + osVersion.replacing(".", with: "-")
}

private func resolveSimulator(
    request: SimulatorRequest,
    mode: SimulatorMode,
    deviceList: DeviceList,
    loadRuntimes: () throws -> RuntimeList,
    createDevice: (_ name: String, _ deviceTypeID: String, _ runtimeID: String) throws -> String
) throws -> String? {
    let simulator = request.simulator.trimmingCharacters(in: .whitespacesAndNewlines)
    let osVersion = request.osVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let explicitID = request.explicitID.trimmingCharacters(in: .whitespacesAndNewlines)
    let destination = request.destination.trimmingCharacters(in: .whitespacesAndNewlines)

    if !explicitID.isEmpty && !name.isEmpty {
        throw SimulatorScriptError(description: "Pass either SIMULATOR_ID or SIMULATOR_NAME, not both.")
    }

    // Reject CI simulators before lookup or creation so local runs never touch CI data.
    if isCISimulatorName(simulator) {
        throw SimulatorScriptError(
            description: "Refusing to use simulator \"\(simulator)\": CI simulators are reserved for CI.")
    }
    if isCISimulatorName(name) {
        throw SimulatorScriptError(
            description: "Refusing to use simulator \"\(name)\": CI simulators are reserved for CI.")
    }
    if isCISimulatorName(explicitID) {
        throw SimulatorScriptError(
            description: "Refusing to use simulator \"\(explicitID)\": CI simulators are reserved for CI.")
    }

    let fields = destinationFields(destination)
    for key in ["name", "id"] {
        if let value = fields[key], isCISimulatorName(value) {
            throw SimulatorScriptError(
                description: "Refusing to use destination \"\(destination)\": CI simulators are reserved for CI.")
        }
    }

    let allDevices = deviceList.devices.values.flatMap { $0 }
    let ciTargets = [explicitID, fields["id"] ?? "", fields["name"] ?? ""].filter { !$0.isEmpty }
    for target in ciTargets {
        if let matched = allDevices.first(where: {
            ($0.udid.caseInsensitiveCompare(target) == .orderedSame || $0.name == target)
                && isCISimulatorName($0.name)
        }) {
            throw SimulatorScriptError(
                description:
                    "Refusing to use simulator \"\(matched.name)\" (\(matched.udid)): CI simulators are reserved for CI."
            )
        }
    }

    if !explicitID.isEmpty {
        return explicitID
    }

    let iosDevices: [RuntimeDevice] = deviceList.devices.keys.sorted()
        .filter { $0.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-") }
        .flatMap { key in
            (deviceList.devices[key] ?? [])
                .filter { $0.available && !isCISimulatorName($0.name) }
                .map { RuntimeDevice(runtimeKey: key, device: $0) }
        }

    let targetSuffix = runtimeSuffix(for: osVersion)

    if !name.isEmpty {
        let targetMatches = iosDevices.filter {
            $0.runtimeKey.hasSuffix(targetSuffix) && $0.device.name == name
        }
        if targetMatches.count == 1 {
            return targetMatches[0].device.udid
        }
        if targetMatches.count > 1 {
            let listing = targetMatches.map { "  - \($0.device.name) (\($0.device.udid))" }.joined(separator: "\n")
            throw SimulatorScriptError(
                description:
                    "Multiple simulators are named \"\(name)\" on iOS \(osVersion):\n\(listing)\nPass SIMULATOR_ID=\"<udid>\"."
            )
        }

        let anyMatches = iosDevices.filter { $0.device.name == name }
        if anyMatches.count == 1 {
            return anyMatches[0].device.udid
        }
        if anyMatches.count > 1 {
            let listing = anyMatches.map { "  - \($0.device.name) (\($0.device.udid))" }.joined(separator: "\n")
            throw SimulatorScriptError(
                description:
                    "Multiple simulators are named \"\(name)\":\n\(listing)\nPass SIMULATOR_ID=\"<udid>\"."
            )
        }

        if mode == .resolve {
            return nil
        }

        let runtimeList = try loadRuntimes()
        guard
            let runtime = runtimeList.runtimes.first(where: {
                $0.available
                    && $0.identifier.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-")
                    && ($0.identifier.hasSuffix(targetSuffix) || $0.version == osVersion)
            })
        else {
            throw SimulatorScriptError(
                description: "iOS \(osVersion) runtime is unavailable. Pass SIMULATOR_OS=<version>.")
        }

        guard
            let deviceType = (runtime.supportedDeviceTypes ?? []).first(where: { $0.name == simulator })
        else {
            throw SimulatorScriptError(
                description:
                    "Device type \"\(simulator)\" is not supported on iOS \(osVersion). Pass SIMULATOR=\"<device>\"."
            )
        }

        let createdID = try createDevice(name, deviceType.identifier, runtime.identifier)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !createdID.isEmpty else {
            throw SimulatorScriptError(description: "xcrun simctl create did not return a simulator UDID.")
        }
        return createdID
    }

    let running = iosDevices.filter { $0.device.isBooted }
    if running.count > 1 {
        let listing = running
            .sorted { ($0.device.name, $0.device.udid) < ($1.device.name, $1.device.udid) }
            .map { "  - \($0.device.name) (\($0.device.udid))" }
            .joined(separator: "\n")
        throw SimulatorScriptError(
            description:
                "Multiple non-CI iOS simulators are booted:\n\(listing)\nPass SIMULATOR_NAME=\"<unique name>\" or SIMULATOR_ID=\"<udid>\"."
        )
    }
    if running.count == 1 {
        return running[0].device.udid
    }

    if let fallback = iosDevices.first(where: {
        $0.runtimeKey.hasSuffix(targetSuffix) && $0.device.name == simulator
    }) {
        return fallback.device.udid
    }

    throw SimulatorScriptError(
        description:
            "No running non-CI iOS simulator was found, and fallback \(simulator) (iOS \(osVersion)) is unavailable."
    )
}

private func runSimctl(_ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl"] + arguments
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    // Drain stderr concurrently so large diagnostic output cannot stall stdout.
    var errorData = Data()
    let stderrGroup = DispatchGroup()
    stderrGroup.enter()
    DispatchQueue.global().async {
        errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        stderrGroup.leave()
    }
    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    stderrGroup.wait()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw SimulatorScriptError(
            description: message.isEmpty ? "xcrun simctl \(arguments.joined(separator: " ")) failed." : message)
    }
    return outputData
}

private func parseArguments(_ arguments: [String]) throws -> (SimulatorMode, SimulatorRequest) {
    guard arguments.count >= 2, let mode = SimulatorMode(rawValue: arguments[1]) else {
        throw SimulatorScriptError(
            description:
                "Usage: simulator.swift <resolve|ensure> [--simulator MODEL] [--os VERSION] [--name NAME] [--id UDID] [--destination DEST]"
        )
    }
    var simulator = "iPhone 17"
    var osVersion = "27.0"
    var name = ""
    var explicitID = ""
    var destination = ""
    var index = 2
    while index < arguments.count {
        let flag = arguments[index]
        guard index + 1 < arguments.count else {
            throw SimulatorScriptError(description: "Missing value for \(flag).")
        }
        let value = arguments[index + 1]
        switch flag {
        case "--simulator": simulator = value
        case "--os": osVersion = value
        case "--name": name = value
        case "--id": explicitID = value
        case "--destination": destination = value
        default:
            throw SimulatorScriptError(description: "Unknown option: \(flag).")
        }
        index += 2
    }
    return (
        mode,
        SimulatorRequest(
            simulator: simulator,
            osVersion: osVersion,
            name: name,
            explicitID: explicitID,
            destination: destination
        )
    )
}

#if !SIMULATOR_SCRIPT_TESTS
    do {
        let (mode, request) = try parseArguments(CommandLine.arguments)
        let devicesData = try runSimctl(["list", "devices", "--json"])
        let deviceList = try JSONDecoder().decode(DeviceList.self, from: devicesData)
        let udid = try resolveSimulator(
            request: request,
            mode: mode,
            deviceList: deviceList,
            loadRuntimes: {
                let runtimesData = try runSimctl(["list", "runtimes", "--json"])
                return try JSONDecoder().decode(RuntimeList.self, from: runtimesData)
            },
            createDevice: { name, deviceTypeID, runtimeID in
                let data = try runSimctl(["create", name, deviceTypeID, runtimeID])
                return String(decoding: data, as: UTF8.self)
            }
        )
        if let udid {
            print(udid)
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
#endif
