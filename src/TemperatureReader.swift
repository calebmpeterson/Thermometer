import Foundation
import IOKit

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPowerLimit: UInt32 = 0
    var gpuPowerLimit: UInt32 = 0
    var memoryPowerLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

final class SMCReader {
    private let readKeySelector: UInt32 = 2
    private let readBytesCommand: UInt8 = 5
    private let readKeyInfoCommand: UInt8 = 9
    private let temperatureKeys = ["TC0P", "TC0E", "TC0F", "TC0D", "TC0H"]

    private var connection: io_connect_t = 0

    init?() {
        let matchingDictionary = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDictionary)
        guard service != IO_OBJECT_NULL else {
            return nil
        }

        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            return nil
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readCPUTemperatureFahrenheit() -> Double? {
        for key in temperatureKeys {
            if let celsius = readTemperature(forKey: key) {
                return (celsius * 9.0 / 5.0) + 32.0
            }
        }

        return nil
    }

    private func readTemperature(forKey key: String) -> Double? {
        guard let keyCode = fourCharacterCode(from: key) else {
            return nil
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        input.key = keyCode
        input.data8 = readKeyInfoCommand

        let keyInfoResult = IOConnectCallStructMethod(
            connection,
            readKeySelector,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )

        guard keyInfoResult == KERN_SUCCESS else {
            return nil
        }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = readBytesCommand
        output = SMCKeyData()
        outputSize = MemoryLayout<SMCKeyData>.stride

        let readResult = IOConnectCallStructMethod(
            connection,
            readKeySelector,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )

        guard readResult == KERN_SUCCESS else {
            return nil
        }

        let bytes = bytesArray(from: output.bytes)
        guard bytes.count >= 2 else {
            return nil
        }

        let rawValue = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        return Double(rawValue) / 256.0
    }

    private func fourCharacterCode(from string: String) -> UInt32? {
        let utf8 = Array(string.utf8)
        guard utf8.count == 4 else {
            return nil
        }

        return utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func bytesArray(from tuple: SMCBytes) -> [UInt8] {
        withUnsafeBytes(of: tuple) { Array($0) }
    }
}

enum SystemMetrics {
    static func readCPUPerformanceLimitPercent() -> Int? {
        guard let maxRatio = readSysctlInt("machdep.xcpm.bootpst"), maxRatio > 0 else {
            return nil
        }

        let limitNames = [
            "machdep.xcpm.hard_plimit_max_100mhz_ratio",
            "machdep.xcpm.soft_plimit_max_100mhz_ratio"
        ]

        let ratios = limitNames.compactMap(readSysctlInt)
        guard let limitedRatio = ratios.min() else {
            return nil
        }

        let percent = (Double(limitedRatio) / Double(maxRatio)) * 100.0
        let clampedPercent = min(max(percent, 0.0), 100.0)
        return Int(clampedPercent.rounded())
    }

    private static func readSysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size

        let result = name.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        guard result == 0 else {
            return nil
        }

        return Int(value)
    }
}
