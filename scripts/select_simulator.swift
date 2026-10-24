import Foundation

struct SimulatorError: Error, CustomStringConvertible {
    let description: String
}

func selectSimulator(data: Data, arguments: [String]) throws -> String {
    guard arguments == ["cloud"] || arguments.count == 3 && arguments[0] == "local" else {
        throw SimulatorError(description: "Usage: select_simulator.sh cloud | local DEVICE OS")
    }
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let devices = document["devices"] as? [String: [[String: Any]]]
    else { throw SimulatorError(description: "Invalid simctl device list.") }
    // Swift dictionaries do not retain JSON key order. Recover it from the input.
    let text = String(decoding: data, as: UTF8.self)
    let runtimes = devices.keys.sorted {
        let left = text.range(of: "\"\($0)\"")?.lowerBound ?? text.endIndex
        let right = text.range(of: "\"\($1)\"")?.lowerBound ?? text.endIndex
        return left < right
    }
    if arguments[0] == "cloud" {
        for runtime in runtimes where runtime.contains("iOS") {
            if let device = devices[runtime]?.first(where: {
                ($0["name"] as? String)?.hasPrefix("iPhone") == true
                    && $0["isAvailable"] as? Bool != false
            }), let id = device["udid"] as? String, !id.isEmpty {
                return id
            }
        }
        throw SimulatorError(description: "No available iOS iPhone simulator was found.")
    }
    for runtime in runtimes where runtime.hasPrefix("com.apple.CoreSimulator.SimRuntime.iOS-") {
        if let device = devices[runtime]?.first(where: { $0["state"] as? String == "Booted" }),
            let id = device["udid"] as? String
        {
            return id
        }
    }
    let suffix = "iOS-" + arguments[2].replacing(".", with: "-")
    for runtime in runtimes where runtime.hasSuffix(suffix) {
        if let device = devices[runtime]?.first(where: { $0["name"] as? String == arguments[1] }),
            let id = device["udid"] as? String
        {
            return id
        }
    }
    return ""
}

#if !SCRIPT_TESTS
    @main
    struct SimulatorCommand {
        static func main() {
            do {
                print(
                    try selectSimulator(
                        data: FileHandle.standardInput.readDataToEndOfFile(),
                        arguments: Array(CommandLine.arguments.dropFirst())))
            } catch {
                FileHandle.standardError.write(Data("Simulator selection: \(error)\n".utf8))
                exit(1)
            }
        }
    }
#endif
