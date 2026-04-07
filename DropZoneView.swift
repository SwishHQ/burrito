import SwiftUI
import UniformTypeIdentifiers

// Fanned preview stack
struct FannedImageStack: View {
    var images: [NSImage]
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 3)
                    .rotationEffect(.degrees(rotation(for: index, total: images.count)))
                    .offset(x: offsetX(for: index, total: images.count), y: offsetY(for: index, total: images.count))
            }
        }
        .scaleEffect(isPulsing ? 1.05 : 0.95)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    private func rotation(for index: Int, total: Int) -> Double {
        if total == 1 { return 0 }
        if total == 2 { return index == 0 ? -12 : 12 }
        return index == 0 ? -18 : (index == 1 ? 0 : 18)
    }
    private func offsetX(for index: Int, total: Int) -> CGFloat {
        if total == 1 { return 0 }
        if total == 2 { return index == 0 ? -10 : 10 }
        return index == 0 ? -15 : (index == 1 ? 0 : 15)
    }
    private func offsetY(for index: Int, total: Int) -> CGFloat {
        if total == 1 { return 0 }
        if total == 2 { return 2 }
        return index == 1 ? -4 : 6
    }
}

struct DropZoneView: View {
    @Binding var showSettings: Bool
    @StateObject var processor = ImageProcessor()
    @State private var isTargetedPNG = false
    @State private var isTargetedWebP = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ZStack {
                splitZonesView
                processingZoneView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.4), value: processor.isProcessing)
            .padding(2)
            .overlay(borderOverlay)
            .padding(12)
        }
        .frame(width: 340, height: 180)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            Image("MenuIcon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 14, height: 14)
            
            Text("Burrito")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.05))
    }

    private var splitZonesView: some View {
        HStack(spacing: 0) {
            ZStack {
                Rectangle().fill(isTargetedPNG ? Color.white.opacity(0.1) : Color.clear)
                Text("PNG")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isTargetedPNG) { p in handleDrop(p, format: .png) }
            
            Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1).padding(.vertical, 24)
            
            ZStack {
                Rectangle().fill(isTargetedWebP ? Color.white.opacity(0.1) : Color.clear)
                Text("WEBP")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $isTargetedWebP) { p in handleDrop(p, format: .webp) }
        }
        .opacity(processor.isProcessing ? 0 : 1)
        .allowsHitTesting(!processor.isProcessing)
    }

    private var processingZoneView: some View {
        GeometryReader { geo in
            if processor.isProcessing {
                TimelineView(.animation(minimumInterval: 1/60)) { timeline in
                    processingContent(geo: geo, timeline: timeline)
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(processor.isProcessing)
    }

    private func processingContent(geo: GeometryProxy, timeline: TimelineViewDefaultContext) -> some View {
        let elapsedTime = timeline.date.timeIntervalSince(processor.processingStartTime)
        let dropTime = elapsedTime.truncatingRemainder(dividingBy: 2.0)
        let successTime = timeline.date.timeIntervalSince(processor.successStartTime)

        let isSuccess = processor.isSuccess
        let isError = processor.isError
        let isComplete = isSuccess || isError
        
        let rippleTime = isComplete ? successTime : dropTime
        let amplitude: Float = isComplete ? 1.5 : 12.0
        let frequency: Float = isComplete ? 20.0 : 15.0
        let decay: Float     = isComplete ? 5.0 : 8.0
        let speed: Float     = isComplete ? 900.0 : 1000.0

        return ZStack {
            // Background
            ZStack {
                Color.black
                Circle()
                    .fill(isError ? Color.red.opacity(0.6) : Color(red: 0.20, green: 0.764, blue: 0.388).opacity(isSuccess ? 0.6 : 0.3))
                    .frame(width: 160)
                    .blur(radius: 40)
                    .offset(x: -40, y: -20)
                Circle()
                    .fill(isError ? Color.red.opacity(0.3) : Color.white.opacity(0.15))
                    .frame(width: 140)
                    .blur(radius: 40)
                    .offset(x: 50, y: 30)
            }
            .scaleEffect(1.2)
            .layerEffect(
                ShaderLibrary.modernFluid(
                    .float(elapsedTime),
                    .float2(Float(geo.size.width), Float(geo.size.height))
                ),
                maxSampleOffset: CGSize(width: 10, height: 10)
            )

            // Foreground
            VStack(spacing: 12) {
                Spacer()

                if isSuccess {
                    statusView(icon: "checkmark.circle.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4), text: "SUCCESS", savings: processor.savingsPercentage)
                } else if isError {
                    statusView(icon: "exclamationmark.triangle.fill", color: .red, text: processor.errorMessage ?? "ERROR", isError: true)
                } else {
                    processingIndicator
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSuccess)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isError)
        }
        .layerEffect(
            ShaderLibrary.Ripple(
                .float2(Float(geo.size.width / 2), Float(geo.size.height / 2)),
                .float(Float(rippleTime)),
                .float(amplitude),
                .float(frequency),
                .float(decay),
                .float(speed)
            ),
            maxSampleOffset: CGSize(width: 40, height: 40),
            isEnabled: true
        )
    }

    private func statusView(icon: String, color: Color, text: String, isError: Bool = false, savings: Int? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 0)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))

            HStack(spacing: 6) {
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(.white)
                
                if let savings = savings, savings > 0 {
                    Text("-\(savings)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, isError ? 20 : 0)
            .padding(.bottom, 16)
            .transition(.opacity)
        }
    }

    private var processingIndicator: some View {
        VStack(spacing: 12) {
            FannedImageStack(images: processor.processingImages)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))

            Text("PROCESSING \(processor.activeFormat == .png ? "PNG" : "WEBP")")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 16)
                .transition(.opacity)
        }
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(processor.isProcessing ? (processor.isSuccess ? Color.green.opacity(0.4) : (processor.isError ? Color.red.opacity(0.4) : Color.white.opacity(0.3))) : Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            .animation(.easeInOut, value: processor.isProcessing)
    }
    
    private func handleDrop(_ providers: [NSItemProvider], format: TargetFormat) -> Bool {
        guard !processor.isProcessing else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data = data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { processor.processDroppedURLs(urls, to: format) }
        }
        return true
    }
}
