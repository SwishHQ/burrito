import SwiftUI

// Custom Blur Fade Transition
struct BlurFadeModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? 10 : 0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(isActive: true),
            identity: BlurFadeModifier(isActive: false)
        )
    }
}

struct ContentView: View {
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if showSettings {
                SettingsView(showSettings: $showSettings)
                    .transition(.blurFade)
                    .zIndex(1) // Ensures proper layering during transition
            } else {
                DropZoneView(showSettings: $showSettings)
                    .transition(.blurFade)
                    .zIndex(0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            showSettings = false
        }
        
        .frame(width: 340, height: 180)
        .preferredColorScheme(.dark)
        // Spring animation provides a premium feel to the blur transition
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showSettings)
    }
}
