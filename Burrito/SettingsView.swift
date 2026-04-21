import SwiftUI

struct SettingsView: View {
    @Binding var showSettings: Bool
    
    @AppStorage("imageQuality") private var imageQuality: Double = 80.0
    @AppStorage("videoQuality") private var videoQuality: Double = 80.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Back Button
            HStack {
                Button(action: { showSettings = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                
                Spacer()
                Text("Quality Settings")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(white: 0.05))
            
            // Sliders
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    HStack {
                        Text("Image Quality")
                        Spacer()
                        Text("\(Int(imageQuality))")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    
                    Slider(value: $imageQuality, in: 40...100, step: 1)
                        .tint(.white)
                }
                
                VStack(spacing: 2) {
                    HStack {
                        Text("Video Quality")
                        Spacer()
                        Text("\(Int(videoQuality))")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    
                    Slider(value: $videoQuality, in: 40...100, step: 1)
                        .tint(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            Spacer(minLength: 0)
        }
        .frame(width: 340, height: 180)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}
