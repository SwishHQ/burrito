import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static let burritoAmber = Color(red: 0.91, green: 0.66, blue: 0.09)
}

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

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat = 0
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 6 * sin(shakes * .pi * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

struct ErrorIconView: View {
    @State private var shakeCount: CGFloat = 0

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 42))
            .foregroundColor(.burritoAmber)
            .shadow(color: .burritoAmber.opacity(0.5), radius: 8, x: 0, y: 0)
            .modifier(ShakeEffect(shakes: shakeCount))
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    shakeCount = 3
                }
            }
    }
}

private struct ProcessingLayerView: View {
    @ObservedObject var processor: ImageProcessor

    var body: some View {
        GeometryReader { geo in
            if processor.isProcessing {
                TimelineView(.animation(minimumInterval: 1/60)) { timeline in
                    let elapsedTime = timeline.date.timeIntervalSince(processor.processingStartTime)
                    let dropTime = elapsedTime.truncatingRemainder(dividingBy: 2.0)
                    let successTime = timeline.date.timeIntervalSince(processor.successStartTime)
                    let errorTime = timeline.date.timeIntervalSince(processor.errorStartTime)

                    let isSuccess = processor.isSuccess
                    let isError = processor.isError
                    let rippleParams: (Double, Float, Float, Float, Float) = {
                        if isSuccess { return (successTime, 1.5, 20.0, 5.0, 900.0) }
                        if isError   { return (errorTime,   1.2, 22.0, 7.0, 800.0) }
                        return (dropTime, 12.0, 15.0, 8.0, 1000.0)
                    }()
                    let rippleTime  = rippleParams.0
                    let amplitude   = rippleParams.1
                    let frequency   = rippleParams.2
                    let decay       = rippleParams.3
                    let speed       = rippleParams.4

                    ZStack {
                        backgroundBlobs(geo: geo, elapsedTime: elapsedTime, isError: isError, isSuccess: isSuccess)
                        foregroundContent(isSuccess: isSuccess, isError: isError)
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
                .transition(.opacity)
            }
        }
        .allowsHitTesting(processor.isProcessing)
    }

    @ViewBuilder
    private func backgroundBlobs(geo: GeometryProxy, elapsedTime: TimeInterval, isError: Bool, isSuccess: Bool) -> some View {
        ZStack {
            Color.black
            Circle()
                .fill(
                    (isError
                        ? Color.burritoAmber
                        : Color(red: 0.20, green: 0.764, blue: 0.388))
                    .opacity(isSuccess ? 0.6 : (isError ? 0.5 : 0.3))
                )
                .frame(width: 160)
                .blur(radius: isError ? 35 : 40)
                .offset(x: -40, y: -20)
            Circle()
                .fill(Color.white.opacity(0.15))
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
    }

    @ViewBuilder
    private func foregroundContent(isSuccess: Bool, isError: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            if isSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.4))
                    .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.5), radius: 8, x: 0, y: 0)
                    .transition(.scale.combined(with: .opacity))
                Text("SUCCESS")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(.white)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            } else if isError {
                ErrorIconView()
                    .transition(.scale.combined(with: .opacity))
                Text("FAILED")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(.white)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            } else {
                FannedImageStack(images: processor.processingImages)
                    .transition(.scale.combined(with: .opacity))
                Text("PROCESSING \(processor.activeFormat == .png ? "PNG" : "WEBP")")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.10, dampingFraction: 0.65), value: processor.isSuccess)
        .animation(.spring(response: 0.08, dampingFraction: 0.70), value: processor.isError)
    }
}

struct DropZoneView: View {
    @Binding var showSettings: Bool
    @StateObject var processor = ImageProcessor()
    @State private var isTargetedPNG = false
    @State private var isTargetedWebP = false

    private var borderStrokeColor: Color {
        let isProcessing = processor.isProcessing
        let isSuccess = processor.isSuccess
        let isError = processor.isError
        
        if isProcessing {
            if isSuccess {
                return Color.green.opacity(0.4)
            }
            if isError {
                return Color.burritoAmber.opacity(0.4)
            }
            return Color.white.opacity(0.3)
        }
        return Color.white.opacity(0.15)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            
            // Central Area - Layered Opacity Architecture
            ZStack {
                
                // LAYER 1: SPLIT ZONES (Fades out when processing)
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
                .allowsHitTesting(!processor.isProcessing) // Disables drops when hidden
                
                
                // LAYER 2: COMBINED PROCESSING ZONE (Fades in when processing)
                ProcessingLayerView(processor: processor)
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.4), value: processor.isProcessing)
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderStrokeColor, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    .animation(.easeInOut, value: processor.isProcessing)
            )
            .padding(12)
        }
        .frame(width: 340, height: 180)
        .background(Color.black)
        .preferredColorScheme(.dark)
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

