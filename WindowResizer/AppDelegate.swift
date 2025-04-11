//
//  AppDelegate.swift
//  WindowResizer
//
//  Created by Mihai Leonte on 14.03.2025.
//

import Cocoa
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windowObserver: WindowObserver!
    var userExplicitlyStopped = false
    
    // Default list of apps to ignore
    var ignoredApps = ["Finder", "Terminal", "System Settings", "System Preferences"]
    
    // Launch at login setting
    var launchAtLogin: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            updateLoginItemSettings()
        }
    }
    
    override init() {
        super.init()
        
        // Load saved ignored apps list if available
        if let savedApps = UserDefaults.standard.stringArray(forKey: "ignoredApps") {
            ignoredApps = savedApps
            print("Loaded saved ignored apps: \(ignoredApps.joined(separator: ", "))")
        }
        
        windowObserver = WindowObserver(ignoredApps: ignoredApps)
    }
    func updateLoginItemSettings() {
        // Get the app's bundle identifier
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            // Try using modern API first (macOS 13+)
            if #available(macOS 13.0, *) {
                do {
                    try SMAppService.mainApp.register()
                    print("Registered app to launch at login using SMAppService")
                } catch {
                    print("Failed to register app to launch at login: \(error)")
                    // Fall back to legacy method
                    setLaunchAtLoginLegacy(bundleIdentifier: bundleIdentifier)
                }
            } else {
                // Use legacy method for older macOS versions
                setLaunchAtLoginLegacy(bundleIdentifier: bundleIdentifier)
            }
        } else {
            print("Could not determine bundle identifier")
        }
    }
    
    func setLaunchAtLoginLegacy(bundleIdentifier: String) {
        // Legacy method using SMLoginItemSetEnabled
        if SMLoginItemSetEnabled(bundleIdentifier as CFString, launchAtLogin) {
            print("Successfully \(launchAtLogin ? "enabled" : "disabled") launch at login")
        } else {
            print("Failed to \(launchAtLogin ? "enable" : "disable") launch at login")
        }
    }
            
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        
        // Register for application activation notification to update permissions status
        NotificationCenter.default.addObserver(self, 
            selector: #selector(applicationActivated), 
            name: NSApplication.didBecomeActiveNotification, 
            object: nil)
            
        // Check if we already have accessibility permissions (without prompting)
        if AXIsProcessTrusted() {
            print("Permission already granted - starting window monitoring")
            windowObserver.startMonitoring()
            userExplicitlyStopped = false // Reset flag on initial start
            updateMenu() // Update menu to reflect monitoring state
        } else {
            // Don't request permissions automatically - user will do it manually
            print("Waiting for user to request accessibility permissions")
            updateMenu()
        }
        
        // Set up timer to regularly check permission status
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkPermissionStatus), userInfo: nil, repeats: true)
        
        // Check current login item status
        if launchAtLogin {
            print("App is set to launch at login")
        }
    }
    
    @objc func checkPermissionStatus() {
        // Check if permission status has changed and update menu accordingly
        let hasPermission = AXIsProcessTrusted()
        
        // If we just got permissions and aren't monitoring yet and user didn't explicitly stop it
        if hasPermission && !windowObserver.isMonitoring && !userExplicitlyStopped {
            print("Detected permissions granted - starting monitoring")
            windowObserver.startMonitoring()
            updateMenu()
        }
        
        // If we lost permissions but were monitoring, stop monitoring
        if !hasPermission && windowObserver.isMonitoring {
            print("Detected permissions revoked - stopping monitoring")
            windowObserver.stopMonitoring()
            updateMenu()
        }
    }
    
    @objc func applicationActivated() {
        // Update menu whenever our app becomes active
        updateMenu()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.arrowtriangle.2.outward", accessibilityDescription: "Window Resizer")
        
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        // Add permission status item
        let hasPermission = AXIsProcessTrusted()
        let statusMenuItem = NSMenuItem()
        
        if hasPermission {
            statusMenuItem.title = "✅ Accessibility Permission Granted"
            statusMenuItem.isEnabled = false
            
            // Add Start/Stop options when we have permission
            menu.addItem(NSMenuItem.separator())
            
            if windowObserver.isMonitoring {
                // Show disabled "Monitoring..." option when active
                let monitoringItem = NSMenuItem(title: "Monitoring...", action: nil, keyEquivalent: "")
                monitoringItem.isEnabled = false
                menu.addItem(monitoringItem)
            } else {
                // Show enabled "Start Window Monitoring" when not active
                let startMenuItem = NSMenuItem(title: "Start Window Monitoring", action: #selector(startMonitoring), keyEquivalent: "s")
                menu.addItem(startMenuItem)
            }
            
            let stopMenuItem = NSMenuItem(title: "Stop Window Monitoring", action: #selector(stopMonitoring), keyEquivalent: "p")
            stopMenuItem.isEnabled = windowObserver.isMonitoring
            menu.addItem(stopMenuItem)
            
            menu.addItem(NSMenuItem(title: "Force Resize Current Window", action: #selector(forceResizeCurrent), keyEquivalent: "r"))
            
            // Add Manage Ignored Apps option
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Manage Ignored Apps", action: #selector(manageIgnoredApps), keyEquivalent: "i"))
            
            // Add Launch at Login option
            let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "l")
            launchAtLoginItem.state = launchAtLogin ? .on : .off
            menu.addItem(launchAtLoginItem)
        } else {
            statusMenuItem.title = "⚠️ Request Accessibility Permission"
            statusMenuItem.action = #selector(requestPermission)
            statusMenuItem.target = self
        }
        
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func requestPermission() {
        print("Manually requesting accessibility permission")
        userExplicitlyStopped = false  // Reset the flag when user requests permissions
        
        // Request permission with prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Create a timer to check for permission more frequently right after requesting
        var checkCount = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            // Check if permission was granted
            if AXIsProcessTrusted() {
                // Permission granted, start monitoring
                if !self.windowObserver.isMonitoring {
                    self.windowObserver.startMonitoring()
                }
                self.updateMenu()
                print("Permission granted during quick check - monitoring started")
                timer.invalidate()
            }
            
            // Increase check count and stop the timer after 20 checks (10 seconds)
            checkCount += 1
            if checkCount >= 20 {
                print("Stopped quick permission checks")
                timer.invalidate()
            }
        }
        
        // Make sure the timer doesn't get deallocated
        RunLoop.current.add(timer, forMode: .common)
    }
    
    @objc func startMonitoring() {
        windowObserver.startMonitoring()
        userExplicitlyStopped = false  // Reset the flag when user explicitly starts monitoring
        print("Window monitoring started")
        updateMenu() // Update menu to reflect monitoring state
    }
    
    @objc func stopMonitoring() {
        windowObserver.stopMonitoring()
        userExplicitlyStopped = true  // Set the flag when user explicitly stops monitoring
        print("Window monitoring stopped")
        // Force update the menu immediately
        updateMenu()
    }
    
    @objc func forceResizeCurrent() {
        print("Force resize requested by user")
        windowObserver.resizeCurrentWindow()
    }
    
    @objc func manageIgnoredApps() {
        let alert = NSAlert()
        alert.messageText = "Manage Ignored Apps"
        alert.informativeText = "Enter app names to ignore, separated by commas (e.g., 'Finder, Terminal'):\n\nCurrent ignored apps: \(ignoredApps.joined(separator: ", "))"
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = ignoredApps.joined(separator: ", ")
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let newIgnoredAppsString = inputTextField.stringValue
            let newIgnoredApps = newIgnoredAppsString.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            // Update the ignored apps list
            ignoredApps = newIgnoredApps
            windowObserver.ignoredApps = newIgnoredApps
            
            // Save to UserDefaults
            UserDefaults.standard.set(newIgnoredApps, forKey: "ignoredApps")
            
            print("Updated ignored apps list: \(ignoredApps.joined(separator: ", "))")
        }
    }
    
    @objc func toggleLaunchAtLogin() {
        // Toggle the launch at login setting
        launchAtLogin = !launchAtLogin
        print("Launch at login \(launchAtLogin ? "enabled" : "disabled")")
        
        // Update the menu to reflect the new setting
        updateMenu()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

class WindowObserver {
    var isMonitoring: Bool = false
    var ignoredApps: [String]
    
    init(ignoredApps: [String]) {
        self.ignoredApps = ignoredApps
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return } // Don't register multiple times
        
        // Monitor application activation
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Also monitor application launches
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationLaunched),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        
        isMonitoring = true
        print("Window monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Remove all observers
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        
        isMonitoring = false
        print("Window monitoring stopped - observers removed")
    }

    @objc func applicationActivated(notification: Notification) {
        resizeCurrentWindow()
    }

    @objc func applicationLaunched(notification: Notification) {
        // Wait a bit for the application to fully launch and create windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.resizeCurrentWindow()
        }
    }

    func resizeCurrentWindow() {
        print("Checking if current window needs resizing")
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("Could not determine frontmost application")
            return
        }
        
        let appName = frontmostApp.localizedName ?? "Unknown"
        print("Current window is from: \(appName)")
        
        // Skip system apps and explicitly ignored apps
        let systemApps = ["SystemUIServer", "Control Center", "NotificationCenter", "Window Manager", "Dock"]
        let allIgnoredApps = systemApps + ignoredApps
        
        if allIgnoredApps.contains(where: { appName.contains($0) }) {
            print("Skipping ignored app: \(appName)")
            return
        }
        
        // Create accessibility element for the app
        let appRef = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Get focused window
        var windowRef: AnyObject?
        let error = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        
        if error != .success || windowRef == nil {
            print("Failed to get focused window: \(error)")
            return
        }
        
        // Get the window element
        let windowElement = windowRef as! AXUIElement
        
        // Check if the window is resizable
        var isResizableRef: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, "AXResizable" as CFString, &isResizableRef) == .success,
           let isResizable = isResizableRef as? Bool, !isResizable {
            print("Window is not resizable. Skipping.")
            return
        }
        
        // Get current position and size
        let (currentPosition, currentSize) = getCurrentPositionAndSize(windowElement)
        
        // If we couldn't get position or size, exit
        guard let position = currentPosition, let size = currentSize else {
            print("Could not determine current window position or size")
            return
        }
        
        // Determine if it's Xcode to apply special dimensions
        let isXcode = appName.contains("Xcode")
        let targetWidth = isXcode ? 1369 : 1409
        let targetHeight = 918
        let targetX = 60
        let targetY = 38  // Updated to 38 to account for the menu bar
        
        // Calculate if we need to resize or move
        let needsResize = size.width != CGFloat(targetWidth) || size.height != CGFloat(targetHeight)
        let needsMove = position.x != CGFloat(targetX) || position.y != CGFloat(targetY)
        
        if !needsResize && !needsMove {
            print("Window already at the correct position and size. Skipping.")
            return
        }
        
        // Log what we're changing
        if needsMove && needsResize {
            print("Moving and resizing window")
        } else if needsMove {
            print("Moving window")
        } else {
            print("Resizing window")
        }
        
        // Set position if needed
        if needsMove {
            var point = CGPoint(x: targetX, y: targetY)
            let cfPosition = AXValueCreate(AXValueType.cgPoint, &point)
            AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, cfPosition!)
            print("Window moved to: \(point.x), \(point.y)")
        }
        
        // Set size if needed
        if needsResize {
            var size = CGSize(width: targetWidth, height: targetHeight)
            let cfSize = AXValueCreate(AXValueType.cgSize, &size)
            AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, cfSize!)
            print("Window resized to: \(size.width) x \(size.height)")
        }
    }
    
    // Helper function to get current position and size of a window
    func getCurrentPositionAndSize(_ window: AXUIElement) -> (CGPoint?, CGSize?) {
        var position: CGPoint? = nil
        var size: CGSize? = nil
        
        // Get position
        var positionRef: AnyObject?
        var positionValue = CGPoint.zero
        
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
           let posRef = positionRef,
           AXValueGetValue(posRef as! AXValue, .cgPoint, &positionValue) {
            position = positionValue
            print("Current position: \(positionValue.x), \(positionValue.y)")
        }
        
        // Get size
        var sizeRef: AnyObject?
        var sizeValue = CGSize.zero
        
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let szRef = sizeRef,
           AXValueGetValue(szRef as! AXValue, .cgSize, &sizeValue) {
            size = sizeValue
            print("Current size: \(sizeValue.width) x \(sizeValue.height)")
        }
        
        return (position, size)
    }
}
