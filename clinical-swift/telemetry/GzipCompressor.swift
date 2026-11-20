import Foundation
import zlib

nonisolated enum GzipError: Error, Equatable, Sendable {
    case initializationFailed(Int32)
    case compressionFailed(Int32)
    case decompressionFailed(Int32)
}

/// RFC 1952 gzip compression and decompression using system zlib.
nonisolated enum GzipCompressor {
    private static let chunkSize = 16 * 1024

    static func compress(_ input: Data) throws -> Data {
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipError.initializationFailed(initStatus)
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        let finalStatus: Int32 = input.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.bindMemory(to: Bytef.self).baseAddress
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(input.count)

            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }
                if status == Z_STREAM_ERROR {
                    return status
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: buffer[0..<produced])
                }
            } while status == Z_OK || stream.avail_out == 0
            return status
        }

        guard finalStatus == Z_STREAM_END else {
            throw GzipError.compressionFailed(finalStatus)
        }
        return output
    }

    static func decompress(_ input: Data) throws -> Data {
        guard !input.isEmpty else { throw GzipError.decompressionFailed(Z_DATA_ERROR) }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipError.initializationFailed(initStatus)
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        let finalStatus: Int32 = input.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.bindMemory(to: Bytef.self).baseAddress
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(input.count)

            var status: Int32 = Z_OK
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { outBuffer in
                    stream.next_out = outBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: buffer[0..<produced])
                }
            } while status == Z_OK
            return status
        }

        guard finalStatus == Z_STREAM_END else {
            throw GzipError.decompressionFailed(finalStatus)
        }
        return output
    }
}
