import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var startAtLoginMenuItem: NSMenuItem!
    private var observer: NSObjectProtocol?
    private var refreshTimer: Timer?
    private let smcReader = SMCReader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()

        updateStatusItem()
        updateStartAtLoginMenuItemState()

        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        refreshTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStartAtLoginMenuItemState()
    }

    private func updateStatusItem() {
        let state = ProcessInfo.processInfo.thermalState

        let symbolName: String
        switch state {
        case .nominal:
            symbolName = "thermometer.low"
        case .fair:
            symbolName = "thermometer.medium"
        case .serious:
            symbolName = "thermometer.high"
        case .critical:
            symbolName = "exclamationmark.triangle.fill"
        @unknown default:
            symbolName = "questionmark"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true // ensures proper menu bar rendering

        let title: String
        if let temperature = smcReader?.readCPUTemperatureFahrenheit() {
            title = String(format: "%.0f°F", temperature)
        } else {
            title = "--°F"
        }

        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = title
    }

    private func configureMenu() {
        statusMenu.delegate = self

        startAtLoginMenuItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleStartAtLogin(_:)),
            keyEquivalent: ""
        )
        startAtLoginMenuItem.target = self
        statusMenu.addItem(startAtLoginMenuItem)

        statusMenu.addItem(.separator())

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "")
        quitMenuItem.target = self
        statusMenu.addItem(quitMenuItem)

        statusItem.menu = statusMenu
    }

    private func updateStartAtLoginMenuItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            startAtLoginMenuItem.state = .on
        case .requiresApproval:
            startAtLoginMenuItem.state = .mixed
        case .notRegistered, .notFound:
            startAtLoginMenuItem.state = .off
        @unknown default:
            startAtLoginMenuItem.state = .off
        }
    }

    @objc
    private func toggleStartAtLogin(_ sender: Any?) {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .requiresApproval, .notFound:
                try SMAppService.mainApp.register()
            @unknown default:
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }

        updateStartAtLoginMenuItemState()
    }

    @objc
    private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }
}

@main
struct ThermometerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
