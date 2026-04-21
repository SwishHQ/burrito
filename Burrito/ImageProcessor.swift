import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI
import Combine
import AVFoundation

enum TargetFormat: Equatable {
    case png
    case webp
    case mp4
    case webm
    
    var utType: UTType {
        switch self {
        case .png: return .png
        case .webp: return .webP
        case .mp4: return .mpeg4Movie
        case .webm: return UTType("org.webmproject.webm") ?? .movie
        }
    }
}

enum ProcessingStrategy {
    case highQuality // PNG/MP4
    case webOptimized // WEBP/WEBM
}

enum MediaType {
    case image
    case video
    case mixed
    case unknown
}

class ImageProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var isSuccess = false
    @Published var isError = false
    @Published var errorMessage: String? = nil
    @Published var savingsPercentage: Int? = nil
    @Published var activeFormat: TargetFormat? = nil
    @Published var processingStartTime: Date = Date()
    @Published var successStartTime: Date = Date()
    @Published var processingImages: [NSImage] = []
    @Published var detectedMediaType: MediaType = .unknown
    
    func processDroppedURLs(_ urls: [URL], strategy: ProcessingStrategy) {
        let previewCount = min(urls.count, 3)
        var thumbnails: [NSImage] = []
        for i in 0..<previewCount {
            let url = urls[i]
            if let image = NSImage(contentsOf: url) {
                thumbnails.append(image)
            } else {
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1, preferredTimescale: 60)
                if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                    thumbnails.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                }
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.isProcessing = true
            self.isSuccess = false
            self.isError = false
            self.errorMessage = nil
            self.savingsPercentage = nil
            self.activeFormat = nil // We'll set this per file or show a generic one
            self.processingStartTime = Date()
            self.processingImages = thumbnails
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var firstError: String? = nil
            var totalOriginalSize: Int64 = 0
            var totalOptimizedSize: Int64 = 0
            
            for url in urls {
                let format = self.determineTargetFormat(for: url, strategy: strategy)
                let (error, originalSize, optimizedSize) = self.executeShellPipeline(sourceURL: url, targetFormat: format)
                if let error = error {
                    firstError = error
                    break
                }
                totalOriginalSize += originalSize
                totalOptimizedSize += optimizedSize
            }
            
            DispatchQueue.main.async {
                if firstError == nil && !urls.isEmpty {
                    // Calculate savings
                    if totalOriginalSize > 0 {
                        let savings = Double(totalOriginalSize - totalOptimizedSize) / Double(totalOriginalSize)
                        self.savingsPercentage = max(0, Int(savings * 100))
                    }

                    // 1. Files physically exist. Trigger Success State.
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        self.isSuccess = true
                        self.successStartTime = Date()
                    }
                    
                    // 2. Hide UI after 3.5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.isProcessing = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.isSuccess = false
                            self.savingsPercentage = nil
                            self.activeFormat = nil
                            self.processingImages = []
                        }
                    }
                } else {
                    // FAILURE STATE: Show Error UI then reset
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        self.isError = true
                        self.errorMessage = firstError ?? "Unknown error occurred"
                        self.successStartTime = Date() // Use this for ripple timing
                    }
                    
                    // Hide UI after 4 seconds (slightly longer to read error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.isProcessing = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.isError = false
                            self.errorMessage = nil
                            self.savingsPercentage = nil
                            self.activeFormat = nil
                            self.processingImages = []
                        }
                    }
                }
            }
        }
    }
    
    private func determineTargetFormat(for url: URL, strategy: ProcessingStrategy) -> TargetFormat {
        let videoTypes: [UTType] = [.movie, .video, .quickTimeMovie, .mpeg4Movie, UTType("org.webmproject.webm")].compactMap { $0 }
        let isVideo: Bool
        if let type = UTType(filenameExtension: url.pathExtension) {
            isVideo = videoTypes.contains(where: { type.conforms(to: $0) })
        } else {
            isVideo = false
        }
        
        switch strategy {
        case .highQuality:
            return isVideo ? .mp4 : .png
        case .webOptimized:
            return isVideo ? .webm : .webp
        }
    }
    
    // MARK: - Hardened Runtime Fix
    /// Programmatically forces macOS to treat the binary as an executable, bypassing Archive stripping
    private func grantExecutablePermissions(to path: String) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        } catch {
            print("Permission grant failed: \(error)")
        }
    }
    
    private func executeShellPipeline(sourceURL: URL, targetFormat: TargetFormat) -> (error: String?, originalSize: Int64, optimizedSize: Int64) {
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
        
        // 1. Define and Create Output Directory
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let optimizedDirectory = parentDirectory.appendingPathComponent("Optimized Files")
        
        do {
            if !FileManager.default.fileExists(atPath: optimizedDirectory.path) {
                try FileManager.default.createDirectory(at: optimizedDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch { return ("FOLDER ERROR", 0, 0) }
        
        // 2. Keep Exact Original Filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        
        if targetFormat == .mp4 || targetFormat == .webm {
            guard let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) else { return ("FFMPEG MISSING", 0, 0) }
            grantExecutablePermissions(to: ffmpegPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension(targetFormat == .mp4 ? "mp4" : "webm")
            let quality = UserDefaults.standard.double(forKey: "videoQuality") > 0 ? UserDefaults.standard.double(forKey: "videoQuality") : 80.0
            
            // Map 40-100 to CRF 32-18
            let crf = Int(32 - ((quality - 40) / 60.0) * 14)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            
            if targetFormat == .mp4 {
                process.arguments = ["-i", sourceURL.path, "-vcodec", "libx264", "-crf", "\(crf)", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-y", finalURL.path]
            } else {
                process.arguments = ["-i", sourceURL.path, "-vcodec", "libvpx-vp9", "-crf", "\(crf)", "-b:v", "0", "-y", finalURL.path]
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                    return (nil, originalSize, optimizedSize)
                } else {
                    return ("CONVERSION FAILED", 0, 0)
                }
            } catch { return ("EXECUTION ERROR", 0, 0) }
            
        } else if targetFormat == .webp {
            guard let cwebpPath = Bundle.main.path(forResource: "cwebp", ofType: nil) else { return ("BINARY MISSING", 0, 0) }
            grantExecutablePermissions(to: cwebpPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("webp")
            let imageQ = UserDefaults.standard.double(forKey: "imageQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "imageQuality")) : 80
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cwebpPath)
            // Upgraded: Added -m 6 (max compression) and -mt (multi-threading)
            process.arguments = ["-q", "\(imageQ)", "-m", "6", "-mt", sourceURL.path, "-o", finalURL.path]
            
            do {
                try process.run()
                process.waitUntilExit()
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                    return (nil, originalSize, optimizedSize)
                } else {
                    return ("CONVERSION FAILED", 0, 0)
                }
            } catch { return ("EXECUTION ERROR", 0, 0) }
            
        } else {
            // STEP 1: Lossy Color Quantization (pngquant)
            guard let pngquantPath = Bundle.main.path(forResource: "pngquant", ofType: nil) else { return ("BINARY MISSING", 0, 0) }
            grantExecutablePermissions(to: pngquantPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("png")
            let pngMax = UserDefaults.standard.double(forKey: "imageQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "imageQuality")) : 80
            let pngMin = max(0, pngMax - 15)
            
            let process1 = Process()
            process1.executableURL = URL(fileURLWithPath: pngquantPath)
            // Upgraded: Added --speed 1 (max effort) and --strip (removes metadata bloat)
            process1.arguments = ["--quality=\(pngMin)-\(pngMax)", "--speed", "1", "--strip", "--force", sourceURL.path, "--output", finalURL.path]
            
            do {
                try process1.run()
                process1.waitUntilExit()
                guard process1.terminationStatus == 0 && FileManager.default.fileExists(atPath: finalURL.path) else {
                    return ("OPTIMIZATION FAILED", 0, 0)
                }
            } catch { return ("EXECUTION ERROR", 0, 0) }
            
            // STEP 2: Lossless Deflation (oxipng)
            // Fails silently and returns the pngquant version if oxipng isn't bundled yet
            guard let oxipngPath = Bundle.main.path(forResource: "oxipng", ofType: nil) else { 
                let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                return (nil, originalSize, optimizedSize)
            }
            grantExecutablePermissions(to: oxipngPath)
            
            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: oxipngPath)
            // -o 4 is optimal max effort. Overwrites the file in-place.
            process2.arguments = ["-o", "4", "--strip", "safe", finalURL.path]
            
            do {
                try process2.run()
                process2.waitUntilExit()
                let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                return (nil, originalSize, optimizedSize)
            } catch { 
                let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
                return (nil, originalSize, optimizedSize)
            }
        }
    }
}
