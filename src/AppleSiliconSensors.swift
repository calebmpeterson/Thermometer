import Foundation
import IOKit

// Apple Silicon has no SMC CPU temp keys or xcpm sysctls, so this reads the
// private HID sensor service and the IOPM CPU power status instead.
final class HIDTemperatureReader {
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16
    private static let cpuSensorNameFragments = ["tdie", "MTR Temp Sensor"]

    private let client: CFTypeRef
    private let copyServices: CopyServices
    private let copyEvent: CopyEvent
    private let copyProperty: CopyProperty
    private let getFloatValue: GetFloatValue

    init?() {
        guard
            let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
            let createSymbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
            let setMatchingSymbol = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
            let copyServicesSymbol = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
            let copyEventSymbol = dlsym(handle, "IOHIDServiceClientCopyEvent"),
            let copyPropertySymbol = dlsym(handle, "IOHIDServiceClientCopyProperty"),
            let getFloatValueSymbol = dlsym(handle, "IOHIDEventGetFloatValue")
        else {
            return nil
        }

        let create = unsafeBitCast(createSymbol, to: CreateClient.self)
        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }

        let setMatching = unsafeBitCast(setMatchingSymbol, to: SetMatching.self)
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)

        self.client = client
        copyServices = unsafeBitCast(copyServicesSymbol, to: CopyServices.self)
        copyEvent = unsafeBitCast(copyEventSymbol, to: CopyEvent.self)
        copyProperty = unsafeBitCast(copyPropertySymbol, to: CopyProperty.self)
        getFloatValue = unsafeBitCast(getFloatValueSymbol, to: GetFloatValue.self)
    }

    func readCPUTemperatureFahrenheit() -> Double? {
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return nil
        }

        let celsiusReadings = services.compactMap { service -> Double? in
            guard isCPUSensor(service), let celsius = readCelsius(from: service) else {
                return nil
            }

            return celsius
        }

        guard let hottest = celsiusReadings.max() else {
            return nil
        }

        return (hottest * 9.0 / 5.0) + 32.0
    }

    private func isCPUSensor(_ service: AnyObject) -> Bool {
        guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else {
            return false
        }

        return Self.cpuSensorNameFragments.contains { name.contains($0) }
    }

    private func readCelsius(from service: AnyObject) -> Double? {
        guard let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
            return nil
        }

        let celsius = getFloatValue(event, Self.temperatureField)
        let isPlausible = celsius > 0 && celsius < 150
        return isPlausible ? celsius : nil
    }
}

final class AppleSiliconSensorReader: SensorReader {
    private typealias CopyCPUPowerStatus = @convention(c) (UnsafeMutablePointer<Unmanaged<CFDictionary>?>) -> Int32

    private let temperatureReader = HIDTemperatureReader()

    func cpuTemperatureFahrenheit() -> Double? {
        temperatureReader?.readCPUTemperatureFahrenheit()
    }

    // pmset -g therm reads the same status; nothing recorded means no throttling.
    func cpuPerformanceLimitPercent() -> Int? {
        guard
            let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
            let symbol = dlsym(handle, "IOPMCopyCPUPowerStatus")
        else {
            return nil
        }

        var status: Unmanaged<CFDictionary>?
        let copyStatus = unsafeBitCast(symbol, to: CopyCPUPowerStatus.self)
        guard copyStatus(&status) == 0, let dictionary = status?.takeRetainedValue() as? [String: Any] else {
            return 100
        }

        return (dictionary["CPU_Speed_Limit"] as? NSNumber)?.intValue ?? 100
    }
}
