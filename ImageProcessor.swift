import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI
import Combine

enum TargetFormat: Equatable {
    case png
    case webp
    
    var utType: UTType {
        switch self {
        case .png: return .png
        case .webp: return .webP
        }
    }
}

class ImageProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var isSuccess = false
    @Published var activeFormat: TargetFormat? = nil
    @Published var processingStartTime: Date = Date()
    @Published var successStartTime: Date = Date()
    @Published var processingImages: [NSImage] = []
    @Published var isError = false
    @Published var errorStartTime: Date = Date()
    
    func processDroppedURLs(_ urls: [URL], to targetFormat: TargetFormat) {
        let previewCount = min(urls.count, 3)
        var thumbnails: [NSImage] = []
        for i in 0..<previewCount {
            if let image = NSImage(contentsOf: urls[i]) { thumbnails.append(image) }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.isProcessing = true
            self.isSuccess = false
            self.isError = false
            self.activeFormat = targetFormat
            self.processingStartTime = Date()
            self.processingImages = thumbnails
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSucceeded = true
            
            // Track actual success for each file
            for url in urls {
                let success = self.executeShellPipeline(sourceURL: url, targetFormat: targetFormat)
                if !success { allSucceeded = false }
            }
            
            DispatchQueue.main.async {
                if allSucceeded && !urls.isEmpty {
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
                            guard !self.isProcessing else { return }
                            self.isSuccess = false
                            self.activeFormat = nil
                            self.processingImages = []
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.70)) {
                        self.isError = true
                        self.errorStartTime = Date()
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.isProcessing = false
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            guard !self.isProcessing else { return }
                            self.isError = false
                            self.activeFormat = nil
                            self.processingImages = []
                        }
                    }
                }
            }
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
    
    private func executeShellPipeline(sourceURL: URL, targetFormat: TargetFormat) -> Bool {
        // 1. Define and Create Output Directory
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let optimizedDirectory = parentDirectory.appendingPathComponent("Optimized Files")
        
        do {
            if !FileManager.default.fileExists(atPath: optimizedDirectory.path) {
                try FileManager.default.createDirectory(at: optimizedDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch { return false }
        
        // 2. Keep Exact Original Filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        
        if targetFormat == .webp {
            guard let cwebpPath = Bundle.main.path(forResource: "cwebp", ofType: nil) else { return false }
            grantExecutablePermissions(to: cwebpPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("webp")
            let webpQ = UserDefaults.standard.double(forKey: "webpQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "webpQuality")) : 80
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cwebpPath)
            // Upgraded: Added -m 6 (max compression) and -mt (multi-threading)
            process.arguments = ["-q", "\(webpQ)", "-m", "6", "-mt", sourceURL.path, "-o", finalURL.path]
            
            do {
                try process.run()
                process.waitUntilExit()
                return FileManager.default.fileExists(atPath: finalURL.path)
            } catch { return false }
            
        } else {
            // STEP 1: Lossy Color Quantization (pngquant)
            guard let pngquantPath = Bundle.main.path(forResource: "pngquant", ofType: nil) else { return false }
            grantExecutablePermissions(to: pngquantPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("png")
            let pngMax = UserDefaults.standard.double(forKey: "pngQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "pngQuality")) : 80
            let pngMin = max(0, pngMax - 15)
            
            let process1 = Process()
            process1.executableURL = URL(fileURLWithPath: pngquantPath)
            // Upgraded: Added --speed 1 (max effort) and --strip (removes metadata bloat)
            process1.arguments = ["--quality=\(pngMin)-\(pngMax)", "--speed", "1", "--strip", "--force", sourceURL.path, "--output", finalURL.path]
            
            do {
                try process1.run()
                process1.waitUntilExit()
                guard process1.terminationStatus == 0 && FileManager.default.fileExists(atPath: finalURL.path) else { return false }
            } catch { return false }
            
            // STEP 2: Lossless Deflation (oxipng)
            // Fails silently and returns the pngquant version if oxipng isn't bundled yet
            guard let oxipngPath = Bundle.main.path(forResource: "oxipng", ofType: nil) else { return true }
            grantExecutablePermissions(to: oxipngPath)
            
            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: oxipngPath)
            // -o 4 is optimal max effort. Overwrites the file in-place.
            process2.arguments = ["-o", "4", "--strip", "safe", finalURL.path]
            
            do {
                try process2.run()
                process2.waitUntilExit()
                return process2.terminationStatus == 0
            } catch { return true } // Return true because Step 1 still succeeded
        }
    }
}
