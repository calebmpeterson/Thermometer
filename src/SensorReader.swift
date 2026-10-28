protocol SensorReader {
    func cpuTemperatureFahrenheit() -> Double?
    func cpuPerformanceLimitPercent() -> Int?
}

// Apple Silicon's SMC answers Intel keys with bogus values, so each platform gets its own reader
func makePlatformSensorReader() -> SensorReader {
    #if arch(arm64)
    return AppleSiliconSensorReader()
    #else
    return IntelSensorReader()
    #endif
}
