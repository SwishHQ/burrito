import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

// Transparent Overlay to intercept drags
class MenuBarDragView: NSView {
    var onDragEntered: ((MediaType) -> Void)?
    
    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let type = determineMediaType(for: urls)
            onDragEntered?(type)
        }
        return []
    }
    
    private func determineMediaType(for urls: [URL]) -> MediaType {
        let videoTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, UTType("org.webmproject.webm")].compactMap { $0 }
        let imageTypes: [UTType] = [.image, .png, .jpeg, .webP, .gif]
        
        var hasVideo = false
        var hasImage = false
        
        for url in urls {
            if let type = UTType(filenameExtension: url.pathExtension) {
                if videoTypes.contains(where: { type.conforms(to: $0) }) {
                    hasVideo = true
                } else if imageTypes.contains(where: { type.conforms(to: $0) }) {
                    hasImage = true
                }
            }
        }
        
        if hasVideo && hasImage { return .mixed }
        if hasVideo { return .video }
        if hasImage { return .image }
        return .unknown
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var rightClickMenu: NSMenu!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let contentView = ContentView()
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 180)
        popover.behavior = .transient
        popover.animates = true
        popover.setValue(true, forKeyPath: "shouldHideAnchor")

        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentViewController?.view.window?.backgroundColor = NSColor.black
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let customIcon = NSImage(named: "MenuIcon") {
                customIcon.isTemplate = true
                customIcon.size = NSSize(width: 18, height: 18)
                button.image = customIcon
            } else {
                button.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "SwishDrop")
            }
            
            // Configure button to receive both left and right clicks
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleMenuClick(_:))
            
            setupRightClickMenu()
            
            let dragView = MenuBarDragView()
            dragView.frame = button.bounds
            dragView.autoresizingMask = [.width, .height]
            dragView.onDragEntered = { [weak self] type in
                self?.openPopoverForDrag(with: type)
            }
            button.addSubview(dragView)
        }
    }
    
    func setupRightClickMenu() {
        rightClickMenu = NSMenu()
        
        let loginItem = NSMenuItem(title: "Launch on Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        // Check actual system status to set initial checkmark
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        rightClickMenu.addItem(loginItem)
        
        rightClickMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Burrito", action: #selector(quitApp), keyEquivalent: "q")
        rightClickMenu.addItem(quitItem)
    }
    
    @objc func handleMenuClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right Click: Temporarily assign menu, perform click, remove menu
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left Click: Toggle Popover
            if let button = statusItem.button {
                if popover.isShown {
                    popover.performClose(sender)
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
    
    @objc func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            print("Failed to toggle login item: \(error)")
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func openPopoverForDrag(with type: MediaType) {
        if let contentView = (popover.contentViewController as? NSHostingController<ContentView>)?.rootView {
            // We need to access the processor from ContentView or pass it down
            // For now, let's assume we can set it via Notification or direct access if we refactor
        }
        
        // Actually, let's post a notification to update the processor's state
        NotificationCenter.default.post(name: Notification.Name("MediaDragEntered"), object: type)

        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
