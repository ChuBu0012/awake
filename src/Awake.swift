import AppKit
import Foundation

// MARK: - Awake Menu Bar Application
// Lightweight Native macOS Menu Bar utility for keeping Mac awake.

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isAwakeActive: Bool = false
    private var currentDurationSec: Int = 0
    private var expiresAt: Date?
    private var batteryGuardEnabled: Bool = true
    private var lastCommandSucceeded = false
    
    // Cached dynamic Menu Bar Icons
    private var awakeIcon: NSImage!
    private var asleepIcon: NSImage!
    
    // Lazily resolve and secure the shared CLI/app state directory once.
    private lazy var stateDir: URL = {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configuredPath = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let configHome: URL
        if let configuredPath, configuredPath.hasPrefix("/") {
            configHome = URL(fileURLWithPath: configuredPath, isDirectory: true)
        } else {
            configHome = home.appendingPathComponent(".config", isDirectory: true)
        }
        let directory = configHome.appendingPathComponent("awake", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                NSLog("Awake state directory must not be a symbolic link: %@", directory.path)
                return directory
            }
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            NSLog("Awake could not secure its state directory: %@", error.localizedDescription)
        }
        return directory
    }()
    private var stateFile: URL { stateDir.appendingPathComponent("state.json") }
    private var pidFile: URL { stateDir.appendingPathComponent("caffeinate.pid") }
    
    // UI Menu Items
    private var statusMenuItem: NSMenuItem!
    private var remainingMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var durationMenu: NSMenu!
    private var batteryGuardMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = stateDir
        
        generateMenuBarIcons()
        setupStatusItem()
        updateStateFromSystem()
        
        // Start background polling loop (every 5 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkPeriodicStatus()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Safe exit: ensure sleep is restored when user quits the app
        if isAwakeActive {
            setAwakeState(active: false)
        }
    }
    
    // MARK: - Menu Bar Icons Generation (Stickman Mascot)
    private func generateMenuBarIcons() {
        awakeIcon = createStickmanIcon(awake: true)
        asleepIcon = createStickmanIcon(awake: false)
    }
    
    private func createStickmanIcon(awake: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            
            let strokeColor = NSColor.black.cgColor
            ctx.setStrokeColor(strokeColor)
            
            // 1. Head (circle)
            let center = CGPoint(x: 9.0, y: 8.5)
            let headRadius: CGFloat = 6.8
            let headRect = CGRect(x: center.x - headRadius, y: center.y - headRadius, width: headRadius * 2, height: headRadius * 2)
            
            ctx.setFillColor(NSColor.clear.cgColor)
            ctx.setLineWidth(1.3)
            ctx.strokeEllipse(in: headRect)
            
            if awake {
                // ACTIVE: Wide-eyed, tired eye bags
                // Left Eye
                let leftEyeCenter = CGPoint(x: 6.8, y: 9.5)
                let rightEyeCenter = CGPoint(x: 11.2, y: 9.5)
                let eyeR: CGFloat = 1.6
                
                ctx.setLineWidth(1.0)
                ctx.strokeEllipse(in: CGRect(x: leftEyeCenter.x - eyeR, y: leftEyeCenter.y - eyeR, width: eyeR * 2, height: eyeR * 2))
                ctx.strokeEllipse(in: CGRect(x: rightEyeCenter.x - eyeR, y: rightEyeCenter.y - eyeR, width: eyeR * 2, height: eyeR * 2))
                
                // Pupils (pinpoint staring)
                let pupilR: CGFloat = 0.65
                ctx.setFillColor(strokeColor)
                ctx.fillEllipse(in: CGRect(x: leftEyeCenter.x - pupilR, y: leftEyeCenter.y - pupilR, width: pupilR * 2, height: pupilR * 2))
                ctx.fillEllipse(in: CGRect(x: rightEyeCenter.x - pupilR, y: rightEyeCenter.y - pupilR, width: pupilR * 2, height: pupilR * 2))
                
                // Under-eye bags (tired lines)
                ctx.setLineWidth(0.7)
                ctx.move(to: CGPoint(x: 5.2, y: 7.2))
                ctx.addQuadCurve(to: CGPoint(x: 8.2, y: 7.2), control: CGPoint(x: 6.7, y: 6.2))
                ctx.strokePath()
                
                ctx.move(to: CGPoint(x: 9.8, y: 7.2))
                ctx.addQuadCurve(to: CGPoint(x: 12.8, y: 7.2), control: CGPoint(x: 11.3, y: 6.2))
                ctx.strokePath()
                
                // Mouth (straight, tense line)
                ctx.setLineWidth(1.0)
                ctx.move(to: CGPoint(x: 7.6, y: 4.8))
                ctx.addLine(to: CGPoint(x: 10.4, y: 4.8))
                ctx.strokePath()
            } else {
                // INACTIVE: Peacefully sleeping (-_-)
                ctx.setLineWidth(1.1)
                
                // Left eye (closed arc)
                ctx.move(to: CGPoint(x: 5.4, y: 9.0))
                ctx.addQuadCurve(to: CGPoint(x: 8.0, y: 9.0), control: CGPoint(x: 6.7, y: 8.0))
                ctx.strokePath()
                
                // Right eye (closed arc)
                ctx.move(to: CGPoint(x: 10.0, y: 9.0))
                ctx.addQuadCurve(to: CGPoint(x: 12.6, y: 9.0), control: CGPoint(x: 11.3, y: 8.0))
                ctx.strokePath()
                
                // Mouth (gentle smile)
                ctx.move(to: CGPoint(x: 7.8, y: 5.4))
                ctx.addQuadCurve(to: CGPoint(x: 10.2, y: 5.4), control: CGPoint(x: 9.0, y: 4.6))
                ctx.strokePath()
                
                // Tiny floating 'z' near top-right
                ctx.setLineWidth(0.8)
                ctx.move(to: CGPoint(x: 14.0, y: 16.0))
                ctx.addLine(to: CGPoint(x: 16.5, y: 16.0))
                ctx.addLine(to: CGPoint(x: 14.0, y: 13.5))
                ctx.addLine(to: CGPoint(x: 16.5, y: 13.5))
                ctx.strokePath()
            }
            
            return true
        }
        img.isTemplate = true // Auto adapts to macOS Light/Dark Menu Bar
        return img
    }
    
    // MARK: - Status Bar Setup
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        
        let menu = NSMenu()
        
        // 1. Status Indicator
        statusMenuItem = NSMenuItem(title: "Status: Inactive", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        remainingMenuItem = NSMenuItem(title: "Duration: Standard Sleep", action: nil, keyEquivalent: "")
        remainingMenuItem.isEnabled = false
        menu.addItem(remainingMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Toggle Button
        toggleMenuItem = NSMenuItem(title: "Turn On Awake", action: #selector(toggleAwake), keyEquivalent: "t")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        
        // 3. Duration Presets Submenu
        let durationParent = NSMenuItem(title: "Duration Preset", action: nil, keyEquivalent: "")
        durationMenu = NSMenu()
        
        let presets: [(String, Int)] = [
            ("Indefinite (Until stopped)", 0),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("2 Hours", 2 * 60 * 60),
            ("4 Hours", 4 * 60 * 60),
            ("8 Hours", 8 * 60 * 60)
        ]
        
        for (title, sec) in presets {
            let item = NSMenuItem(title: title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = sec
            durationMenu.addItem(item)
        }
        durationParent.submenu = durationMenu
        menu.addItem(durationParent)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Battery Guard
        batteryGuardMenuItem = NSMenuItem(title: "Battery Guard (Auto-off < 20%)", action: #selector(toggleBatteryGuard), keyEquivalent: "")
        batteryGuardMenuItem.target = self
        batteryGuardMenuItem.state = batteryGuardEnabled ? .on : .off
        menu.addItem(batteryGuardMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Quit
        let quitItem = NSMenuItem(title: "Quit Awake", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateDurationMenuChecks()
    }
    
    // MARK: - UI Updates
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        button.image = isAwakeActive ? awakeIcon : asleepIcon
        button.title = ""
    }
    
    private func updateMenuUI() {
        if isAwakeActive {
            statusMenuItem.title = "Status: ACTIVE (Won't Sleep)"
            toggleMenuItem.title = "Turn Off Awake"
            
            if let exp = expiresAt {
                let remaining = Int(exp.timeIntervalSinceNow)
                if remaining > 0 {
                    let h = remaining / 3600
                    let m = (remaining % 3600) / 60
                    let s = remaining % 60
                    if h > 0 {
                        remainingMenuItem.title = "Remaining: \(h)h \(m)m"
                    } else if m > 0 {
                        remainingMenuItem.title = "Remaining: \(m)m \(s)s"
                    } else {
                        remainingMenuItem.title = "Remaining: \(s)s"
                    }
                } else {
                    remainingMenuItem.title = "Timer Expired"
                }
            } else {
                remainingMenuItem.title = "Duration: Indefinite"
            }
        } else {
            statusMenuItem.title = "Status: Inactive (Normal Sleep)"
            toggleMenuItem.title = "Turn On Awake"
            remainingMenuItem.title = "Duration: Not Running"
        }
        
        updateStatusIcon()
        updateDurationMenuChecks()
    }
    
    private func updateDurationMenuChecks() {
        for item in durationMenu.items {
            item.state = (item.tag == currentDurationSec) ? .on : .off
        }
    }
    
    // MARK: - Actions
    @objc private func toggleAwake() {
        setAwakeState(active: !isAwakeActive, durationSec: currentDurationSec)
    }
    
    @objc private func selectDuration(_ sender: NSMenuItem) {
        currentDurationSec = sender.tag
        if isAwakeActive {
            setAwakeState(active: true, durationSec: currentDurationSec)
        } else {
            updateDurationMenuChecks()
        }
    }
    
    @objc private func toggleBatteryGuard() {
        batteryGuardEnabled.toggle()
        batteryGuardMenuItem.state = batteryGuardEnabled ? .on : .off
    }
    
    @objc private func quitApp() {
        if isAwakeActive {
            setAwakeState(active: false)
        }
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - State Management & System Calls
    private func setAwakeState(active: Bool, durationSec: Int = 0) {
        let cliPath = findAwakeCLI()
        
        if active {
            // Battery guard pre-check
            if batteryGuardEnabled {
                let (isAC, percent) = getBatteryInfo()
                if !isAC && percent <= 20 {
                    sendNotification(title: "Awake Blocked", body: "Battery is at \(percent)% on battery power. Awake mode blocked to protect your Mac.")
                    return
                }
            }
            
            var args = ["on"]
            if durationSec > 0 {
                args.append("\(durationSec)s")
            } else {
                args.append("indefinite")
            }
            
            _ = runCommand(cliPath, arguments: args)
            guard lastCommandSucceeded else {
                sendNotification(title: "Awake Failed", body: "Could not enable sleep prevention. Check permissions and try again.")
                updateStateFromSystem()
                return
            }
            isAwakeActive = true
            currentDurationSec = durationSec
            expiresAt = durationSec > 0 ? Date().addingTimeInterval(TimeInterval(durationSec)) : nil
            sendNotification(title: "Awake Activated", body: durationSec > 0 ? "Awake mode set for \(durationSec / 60) mins." : "Awake mode set indefinitely.")
        } else {
            _ = runCommand(cliPath, arguments: ["off"])
            guard lastCommandSucceeded else {
                sendNotification(title: "Awake Failed", body: "Could not restore the sleep setting. Check permissions and try again.")
                updateStateFromSystem()
                return
            }
            isAwakeActive = false
            expiresAt = nil
            sendNotification(title: "Awake Deactivated", body: "Standard macOS sleep behavior restored.")
        }
        
        updateMenuUI()
    }
    
    private func checkPeriodicStatus() {
        // 1. Check if timer expired
        if isAwakeActive, let exp = expiresAt {
            if Date() >= exp {
                sendNotification(title: "Awake Timer Expired", body: "Scheduled duration reached. Restoring normal sleep.")
                setAwakeState(active: false)
                return
            }
        }
        
        // 2. Battery Guard check
        if isAwakeActive && batteryGuardEnabled {
            let (isAC, percent) = getBatteryInfo()
            if !isAC && percent <= 20 {
                sendNotification(title: "Awake Auto-Disabled", body: "Battery dropped to \(percent)%. Sleep restored to prevent shutdown.")
                setAwakeState(active: false)
                return
            }
        }
        
        // 3. Sync external state (e.g. if toggled via CLI)
        updateStateFromSystem()
    }
    
    private func updateStateFromSystem() {
        let pmsetOutput = runCommand("/usr/bin/pmset", arguments: ["-g"])
        let sleepDisabled = pmsetOutput.contains("SleepDisabled\t1") || pmsetOutput.contains("SleepDisabled 1")
        
        if sleepDisabled != isAwakeActive {
            isAwakeActive = sleepDisabled
        }
        
        // Read JSON state if available
        if let data = try? Data(contentsOf: stateFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let expTimestamp = json["expires_at"] as? Double, expTimestamp > 0 {
                expiresAt = Date(timeIntervalSince1970: expTimestamp)
            } else {
                expiresAt = nil
            }
            if let dur = json["duration_seconds"] as? Int {
                currentDurationSec = dur
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateMenuUI()
        }
    }
    
    // MARK: - Utilities
    private func findAwakeCLI() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(home)/.local/bin/awake",
            "/usr/local/bin/awake",
            Bundle.main.bundlePath + "/Contents/Resources/awake"
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "awake" // fallback to PATH
    }
    
    private func getBatteryInfo() -> (isAC: Bool, percent: Int) {
        let output = runCommand("/usr/bin/pmset", arguments: ["-g", "batt"])
        let isAC = output.contains("AC Power")
        
        var percent = 100
        let regex = try? NSRegularExpression(pattern: "([0-9]{1,3})%")
        if let match = regex?.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let range = Range(match.range(at: 1), in: output) {
            percent = Int(output[range]) ?? 100
        }
        return (isAC, percent)
    }
    
    @discardableResult
    private func runCommand(_ launchPath: String, arguments: [String]) -> String {
        lastCommandSucceeded = false
        let process = Process()
        process.launchPath = launchPath.hasPrefix("/") ? launchPath : "/usr/bin/env"
        process.arguments = launchPath.hasPrefix("/") ? arguments : [launchPath] + arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            lastCommandSucceeded = process.terminationStatus == 0
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            lastCommandSucceeded = false
            return ""
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let script = "display notification \"\(body)\" with title \"\(title)\""
        _ = runCommand("/usr/bin/osascript", arguments: ["-e", script])
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
