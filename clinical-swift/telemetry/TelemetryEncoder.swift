import Foundation

/// Encodes validated NDJSON lines into the request body format expected by a remote log backend.
nonisolated protocol LogBatchEncoder: Sendable {
    var contentType: String { get }
    func encode(_ validNDJSONLines: [Data]) -> Data
}

/// Encodes flat telemetry NDJSON lines as a single JSON array for Axiom ingest.
nonisolated struct AxiomFlatJSONEncoder: LogBatchEncoder {
    let contentType = "application/json"

    func encode(_ validNDJSONLines: [Data]) -> Data {
        guard !validNDJSONLines.isEmpty else { return Data("[]".utf8) }
        let estimatedSize =
            validNDJSONLines.reduce(2) { $0 + $1.count + 1 }
        var output = Data(capacity: estimatedSize)
        output.append(0x5B)  // '['
        for (index, line) in validNDJSONLines.enumerated() {
            if index > 0 {
                output.append(0x2C)  // ','
            }
            output.append(line)
        }
        output.append(0x5D)  // ']'
        return output
    }
}
