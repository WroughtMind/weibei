import CryptoKit
import Foundation

enum PiRuntimeIntegrity {
    /// Computes a lowercase SHA-256 without loading the complete file into memory.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Confirms that a Mach-O executable contains the requested CPU architecture.
    static func hasArchitecture(_ architecture: PiRuntimeArchitecture, executableURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: executableURL),
              let data = try? handle.read(upToCount: 4096),
              data.count >= 8 else {
            return false
        }
        try? handle.close()

        let expectedCPU: UInt32
        switch architecture {
        case .arm64:
            expectedCPU = 0x0100_000c
        case .x86_64:
            expectedCPU = 0x0100_0007
        }
        let magic = Array(data.prefix(4))
        switch magic {
        case [0xcf, 0xfa, 0xed, 0xfe]:
            return uint32(data, offset: 4, endianness: .little) == expectedCPU
        case [0xfe, 0xed, 0xfa, 0xcf]:
            return uint32(data, offset: 4, endianness: .big) == expectedCPU
        case [0xca, 0xfe, 0xba, 0xbe]:
            return fatArchitectures(data, endianness: .big, is64Bit: false).contains(expectedCPU)
        case [0xbe, 0xba, 0xfe, 0xca]:
            return fatArchitectures(data, endianness: .little, is64Bit: false).contains(expectedCPU)
        case [0xca, 0xfe, 0xba, 0xbf]:
            return fatArchitectures(data, endianness: .big, is64Bit: true).contains(expectedCPU)
        case [0xbf, 0xba, 0xfe, 0xca]:
            return fatArchitectures(data, endianness: .little, is64Bit: true).contains(expectedCPU)
        default:
            return false
        }
    }

    private enum Endianness {
        case big
        case little
    }

    /// Reads the CPU types from a universal Mach-O header.
    private static func fatArchitectures(
        _ data: Data,
        endianness: Endianness,
        is64Bit: Bool
    ) -> [UInt32] {
        guard let count = uint32(data, offset: 4, endianness: endianness), count <= 64 else {
            return []
        }
        let entrySize = is64Bit ? 32 : 20
        return (0..<Int(count)).compactMap { index in
            uint32(data, offset: 8 + index * entrySize, endianness: endianness)
        }
    }

    /// Reads an unsigned 32-bit value from binary data.
    private static func uint32(
        _ data: Data,
        offset: Int,
        endianness: Endianness
    ) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else {
            return nil
        }
        let bytes = data[offset..<(offset + 4)]
        switch endianness {
        case .big:
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        case .little:
            return bytes.reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
    }
}
