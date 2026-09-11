import Foundation

public enum CRC32 {
    public struct Accumulator: Sendable {
        private var state: UInt32 = 0xffff_ffff

        public init() {}

        public mutating func update(_ data: Data) {
            for byte in data {
                var value = state ^ UInt32(byte)
                for _ in 0..<8 {
                    value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0)
                }
                state = value
            }
        }

        public var checksum: UInt32 { state ^ 0xffff_ffff }
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var accumulator = Accumulator()
        accumulator.update(data)
        return accumulator.checksum
    }
}
