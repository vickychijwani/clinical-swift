import Foundation

private struct SimulatorTestError: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw SimulatorTestError(description: message)
    }
}

@discardableResult
private func runCommand(_ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw SimulatorTestError(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

private func expectFailure(_ expectedText: String, _ operation: () throws -> String?) throws {
    do {
        let value = try operation()
        throw SimulatorTestError(
            description:
                "Expected failure containing \"\(expectedText)\", got \(String(describing: value))."
        )
    } catch let error as SimulatorScriptError {
        try expect(
            error.description.contains(expectedText),
            "Expected error containing \"\(expectedText)\", got \"\(error.description)\"."
        )
    }
}

private func makeRequest(
    simulator: String = "iPhone 17",
    osVersion: String = "27.0",
    name: String = "",
    explicitID: String = "",
    destination: String = ""
) -> SimulatorRequest {
    SimulatorRequest(
        simulator: simulator,
        osVersion: osVersion,
        name: name,
        explicitID: explicitID,
        destination: destination
    )
}

private func runUnitTests() throws {
    let ios27 = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    let ios26 = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    let ciDevice = SimDevice(
        udid: "CI-UDID-1", name: "CI Simulator 1", state: "Booted", isAvailable: true)
    let bootedOne = SimDevice(udid: "BOOT-1", name: "iPhone 17", state: "Booted", isAvailable: true)
    let bootedTwo = SimDevice(udid: "BOOT-2", name: "Task-B", state: "Booted", isAvailable: true)
    let shutdownFallback = SimDevice(
        udid: "SHUT-1", name: "iPhone 17", state: "Shutdown", isAvailable: true)
    let oldNamed = SimDevice(
        udid: "OLD-NAMED", name: "Task-Old", state: "Shutdown", isAvailable: true)

    let defaultRuntimes = RuntimeList(runtimes: [
        SimRuntime(
            identifier: ios27,
            version: "27.0",
            isAvailable: true,
            supportedDeviceTypes: [
                SimDeviceType(
                    name: "iPhone 17", identifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
                )
            ]
        )
    ])

    let noCreate: (String, String, String) throws -> String = { _, _, _ in
        throw SimulatorTestError(description: "Unexpected simulator creation.")
    }
    let noRuntimes: () throws -> RuntimeList = {
        throw SimulatorTestError(description: "Unexpected runtime listing.")
    }

    // 1. Single booted non-CI simulator succeeds even when a CI simulator is also booted.
    let singleBootedList = DeviceList(devices: [ios26: [ciDevice], ios27: [bootedOne]])
    let singleResult = try resolveSimulator(
        request: makeRequest(),
        mode: .ensure,
        deviceList: singleBootedList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(singleResult == "BOOT-1", "Expected single booted non-CI simulator.")

    // 2. Multiple booted non-CI simulators fail and list each booted simulator.
    let multiBootedList = DeviceList(devices: [ios26: [ciDevice], ios27: [bootedOne, bootedTwo]])
    try expectFailure("Multiple non-CI iOS simulators are booted:") {
        try resolveSimulator(
            request: makeRequest(),
            mode: .ensure,
            deviceList: multiBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
    try expectFailure("SIMULATOR_NAME") {
        try resolveSimulator(
            request: makeRequest(),
            mode: .ensure,
            deviceList: multiBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }

    // 3. Zero booted non-CI simulators fall back to SIMULATOR on SIMULATOR_OS.
    let fallbackList = DeviceList(devices: [ios26: [ciDevice], ios27: [shutdownFallback]])
    let fallbackResult = try resolveSimulator(
        request: makeRequest(),
        mode: .ensure,
        deviceList: fallbackList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(fallbackResult == "SHUT-1", "Expected fallback simulator when none is booted.")

    // 4. Missing fallback fails cleanly.
    try expectFailure("No running non-CI iOS simulator was found") {
        try resolveSimulator(
            request: makeRequest(simulator: "iPhone 99"),
            mode: .ensure,
            deviceList: fallbackList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }

    // 5. SIMULATOR_NAME reuses an existing simulator without creating, even with multiple booted.
    let namedExisting = try resolveSimulator(
        request: makeRequest(name: "Task-B"),
        mode: .ensure,
        deviceList: multiBootedList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(namedExisting == "BOOT-2", "Expected existing named simulator.")

    // 6. SIMULATOR_NAME reuses a unique match on another iOS runtime if absent on SIMULATOR_OS.
    let crossRuntimeList = DeviceList(devices: [ios26: [oldNamed], ios27: [bootedOne, bootedTwo]])
    let crossResult = try resolveSimulator(
        request: makeRequest(name: "Task-Old"),
        mode: .ensure,
        deviceList: crossRuntimeList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(crossResult == "OLD-NAMED", "Expected named simulator from another iOS runtime.")

    // 7. Duplicate SIMULATOR_NAME on the same runtime fails cleanly.
    let duplicateList = DeviceList(devices: [
        ios27: [
            SimDevice(udid: "DUP-1", name: "Shared", state: "Shutdown", isAvailable: true),
            SimDevice(udid: "DUP-2", name: "Shared", state: "Booted", isAvailable: true),
        ]
    ])
    try expectFailure("Multiple simulators are named \"Shared\"") {
        try resolveSimulator(
            request: makeRequest(name: "Shared"),
            mode: .ensure,
            deviceList: duplicateList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }

    // 8. Missing SIMULATOR_NAME returns nil in resolve mode and creates in ensure mode.
    let resolveMissing = try resolveSimulator(
        request: makeRequest(name: "Clinical-new-task"),
        mode: .resolve,
        deviceList: multiBootedList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(resolveMissing == nil, "Resolve mode must not create a simulator.")

    var createdArgs: (String, String, String)?
    let ensuredNew = try resolveSimulator(
        request: makeRequest(name: "Clinical-new-task"),
        mode: .ensure,
        deviceList: multiBootedList,
        loadRuntimes: { defaultRuntimes },
        createDevice: { name, deviceTypeID, runtimeID in
            createdArgs = (name, deviceTypeID, runtimeID)
            return "CREATED-UDID\n"
        }
    )
    try expect(ensuredNew == "CREATED-UDID", "Expected created simulator UDID.")
    try expect(
        createdArgs?.0 == "Clinical-new-task"
            && createdArgs?.1 == "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
            && createdArgs?.2 == ios27,
        "Unexpected simctl create arguments."
    )

    // 9. Missing runtime or device type fails cleanly when creating.
    try expectFailure("iOS 28.0 runtime is unavailable") {
        try resolveSimulator(
            request: makeRequest(osVersion: "28.0", name: "Clinical-new-task"),
            mode: .ensure,
            deviceList: multiBootedList,
            loadRuntimes: { defaultRuntimes },
            createDevice: noCreate
        )
    }
    try expectFailure("Device type \"iPhone 99\" is not supported on iOS 27.0") {
        try resolveSimulator(
            request: makeRequest(simulator: "iPhone 99", name: "Clinical-new-task"),
            mode: .ensure,
            deviceList: multiBootedList,
            loadRuntimes: { defaultRuntimes },
            createDevice: noCreate
        )
    }

    // 10. Explicit SIMULATOR_ID works even when multiple simulators are booted, and rejects conflicting SIMULATOR_NAME.
    let explicitResult = try resolveSimulator(
        request: makeRequest(explicitID: "BOOT-1"),
        mode: .ensure,
        deviceList: multiBootedList,
        loadRuntimes: noRuntimes,
        createDevice: noCreate
    )
    try expect(explicitResult == "BOOT-1", "Expected explicit SIMULATOR_ID.")

    try expectFailure("Pass either SIMULATOR_ID or SIMULATOR_NAME, not both.") {
        try resolveSimulator(
            request: makeRequest(name: "Task-B", explicitID: "BOOT-1"),
            mode: .ensure,
            deviceList: multiBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }

    // 11. CI simulators are rejected across SIMULATOR, SIMULATOR_NAME, SIMULATOR_ID, and DESTINATION.
    try expectFailure("CI simulators are reserved for CI") {
        try resolveSimulator(
            request: makeRequest(simulator: "CI Simulator 1"),
            mode: .ensure,
            deviceList: singleBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
    try expectFailure("CI simulators are reserved for CI") {
        try resolveSimulator(
            request: makeRequest(name: "Clinical CI 2"),
            mode: .ensure,
            deviceList: singleBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
    try expectFailure("CI simulators are reserved for CI") {
        try resolveSimulator(
            request: makeRequest(explicitID: "ci-udid-1"),
            mode: .ensure,
            deviceList: singleBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
    try expectFailure("CI simulators are reserved for CI") {
        try resolveSimulator(
            request: makeRequest(destination: "platform=iOS Simulator,id=CI-UDID-1"),
            mode: .ensure,
            deviceList: singleBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
    try expectFailure("CI simulators are reserved for CI") {
        try resolveSimulator(
            request: makeRequest(destination: "platform=iOS Simulator,name=CI Simulator 1"),
            mode: .ensure,
            deviceList: singleBootedList,
            loadRuntimes: noRuntimes,
            createDevice: noCreate
        )
    }
}

@main
struct SimulatorTests {
    static func main() throws {
        try runUnitTests()

        // Verify the real CLI compiles and rejects invalid arguments cleanly.
        let cli = ProcessInfo.processInfo.environment["SCRIPT_CLI_BIN"]!
        do {
            try runCommand([cli])
            throw SimulatorTestError(description: "CLI accepted missing arguments.")
        } catch let error as SimulatorTestError {
            try expect(error.description.contains("Usage:"), error.description)
        }

        print("PASS simulator: selection, ambiguity, named creation, and CI protection")
    }
}
