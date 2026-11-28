import Foundation

private struct DeviceTestError: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw DeviceTestError(description: message)
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
        throw DeviceTestError(description: String(decoding: data, as: UTF8.self))
    }
    return data
}

private func expectFailure(_ expectedText: String, _ operation: () throws -> String) throws {
    do {
        let value = try operation()
        throw DeviceTestError(
            description: "Expected failure containing \"\(expectedText)\", got \(value)."
        )
    } catch let error as DeviceScriptError {
        try expect(
            error.description.contains(expectedText),
            "Expected error containing \"\(expectedText)\", got \"\(error.description)\"."
        )
    }
}

private func runUnitTests() throws {
    let iphone = CoreDevice(
        identifier: "19903A52-D69C-573D-88F4-8AE24FEF63E8",
        name: "Corp iPhone",
        udid: "00008101-000C4DD83C28801E"
    )
    let simulator = CoreDevice(
        identifier: "F0BD1897-1A7C-497E-9C8A-EAED2F0153CB",
        name: "Corp iPhone",
        udid: "F0BD1897-1A7C-497E-9C8A-EAED2F0153CB",
        platform: "iOS",
        reality: "simulated"
    )
    let watch = CoreDevice(
        identifier: "WATCH-CORE-ID",
        name: "Clinic Watch",
        udid: "WATCH-UDID",
        platform: "watchOS",
        reality: "physical"
    )
    let devices = [simulator, watch, iphone]

    // 1. Resolves by device name while ignoring simulators with the same name.
    try expect(
        try resolvePhysicalIOSDeviceUDID(query: "Corp iPhone", devices: devices)
            == "00008101-000C4DD83C28801E",
        "Expected name lookup to return the physical iOS UDID."
    )

    // 2. Resolves by UDID (case-insensitive) and CoreDevice identifier.
    try expect(
        try resolvePhysicalIOSDeviceUDID(query: "00008101-000c4dd83c28801e", devices: devices)
            == "00008101-000C4DD83C28801E",
        "Expected UDID lookup to match case-insensitively."
    )
    try expect(
        try resolvePhysicalIOSDeviceUDID(
            query: "19903A52-D69C-573D-88F4-8AE24FEF63E8",
            devices: devices
        ) == "00008101-000C4DD83C28801E",
        "Expected CoreDevice identifier lookup to return the physical UDID."
    )

    // 3. Rejects simulators and non-iOS devices.
    try expectFailure("was not found") {
        try resolvePhysicalIOSDeviceUDID(query: "F0BD1897-1A7C-497E-9C8A-EAED2F0153CB", devices: devices)
    }
    try expectFailure("was not found") {
        try resolvePhysicalIOSDeviceUDID(query: "Clinic Watch", devices: devices)
    }

    // 4. Rejects duplicate names and lists their UDIDs.
    let duplicates = [
        iphone,
        CoreDevice(
            identifier: "SECOND-CORE-ID",
            name: "Corp iPhone",
            udid: "00008101-0000000000000002"
        ),
    ]
    try expectFailure("Multiple physical iOS devices are named \"Corp iPhone\"") {
        try resolvePhysicalIOSDeviceUDID(query: "Corp iPhone", devices: duplicates)
    }
    try expectFailure("00008101-0000000000000002") {
        try resolvePhysicalIOSDeviceUDID(query: "Corp iPhone", devices: duplicates)
    }

    // 5. Decodes both modern properties and deprecated devicectl JSON shapes.
    let json = Data(
        """
        {
          "result": {
            "devices": [
              {
                "identifier": "MODERN-ID",
                "properties": {
                  "hardware": { "platform": "iOS", "reality": "physical", "udid": "MODERN-UDID" },
                  "state": { "name": "Modern Phone" }
                }
              },
              {
                "identifier": "LEGACY-ID",
                "hardwareProperties": { "platform": "iOS", "reality": "physical", "udid": "LEGACY-UDID" },
                "deviceProperties": { "name": "Legacy Phone" }
              }
            ]
          }
        }
        """.utf8
    )
    let decoded = try JSONDecoder().decode(DevicectlOutput.self, from: json).result.devices
    try expect(
        try resolvePhysicalIOSDeviceUDID(query: "Modern Phone", devices: decoded) == "MODERN-UDID",
        "Expected modern JSON device to resolve."
    )
    try expect(
        try resolvePhysicalIOSDeviceUDID(query: "Legacy Phone", devices: decoded) == "LEGACY-UDID",
        "Expected legacy JSON device to resolve."
    )
}

@main
struct DeviceTests {
    static func main() throws {
        try runUnitTests()

        let cli = ProcessInfo.processInfo.environment["SCRIPT_CLI_BIN"]!
        do {
            try runCommand([cli])
            throw DeviceTestError(description: "CLI accepted missing arguments.")
        } catch let error as DeviceTestError {
            try expect(error.description.contains("Usage:"), error.description)
        }

        print("PASS device: name, UDID, CoreDevice ID, filtering, and ambiguity checks")
    }
}
