import SwiftUI

@main
struct BurritoApp: App {
    // Binds the AppDelegate to handle the Menu Bar popover
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Using Settings instead of WindowGroup prevents the empty default window from appearing
        Settings {
            EmptyView()
        }
    }
}
