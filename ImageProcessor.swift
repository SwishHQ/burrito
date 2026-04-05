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
    @Published var isError = false
    @Published var errorMessage: String = ""
    @Published var activeFormat: TargetFormat? = nil
    @Published var processingStartTime: Date = Date()
    @Published var successStartTime: Date = Date()
    @Published var processingImages: [NSImage] = []
    
    private let processingTimeout: TimeInterval = 60
    
    /// Processes dropped image URLs and converts them to the target format.
    /// - Parameters:
    ///   - urls: Array of file URLs to process
    ///   - targetFormat: Target image format (PNG or WebP)
    func processDroppedURLs(_ urls: [URL], to targetFormat: TargetFormat) {
        let previewCount = min(urls.count, 3)
        var thumbnails: [NSImage] = []
        for i in 0..<previewCount {
            if let image = NSImage(contentsOf: urls[i]) { thumbnails.append(image) }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            self.isProcessing = true
            self.isSuccess = false
            self.activeFormat = targetFormat
            self.processingStartTime = Date()
            self.processingImages = thumbnails
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var allSucceeded = true
            var lastError: String = ""
            var didTimeout = false
            
            // Track actual success for each file
            for url in urls {
                let result = self.executeShellPipeline(sourceURL: url, targetFormat: targetFormat)
                if !result.success {
                    allSucceeded = false
                    if result.timedOut {
                        didTimeout = true
                        lastError = "Processing timed out"
                    } else if let error = result.errorMessage {
                        lastError = error
                    } else {
                        lastError = "Unknown error"
                    }
                }
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
                            self.isSuccess = false
                            self.isError = false
                            self.errorMessage = ""
                            self.activeFormat = nil
                            self.processingImages = []
                        }
                    }
                } else {
                    // FAILURE STATE: Abort immediately without showing Success checkmark
                    let errorMsg = didTimeout ? "Processing timed out after \(Int(self.processingTimeout)) seconds" : lastError
                    print("Processing failed: \(errorMsg). Aborting UI.")
                    
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self.isError = true
                        self.errorMessage = errorMsg
                        self.isProcessing = false
                        self.activeFormat = nil
                        self.processingImages = []
                    }
                    
                    // Auto-clear error after 3 seconds (check to avoid race condition)
                    let errorMsgToClear = errorMsg
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.errorMessage == errorMsgToClear {
                            withAnimation {
                                self.isError = false
                                self.errorMessage = ""
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Hardened Runtime Fix
    /// Programmatically forces macOS to treat the binary as an executable, bypassing Archive stripping.
    /// - Parameter path: The file path to the binary
    private func grantExecutablePermissions(to path: String) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        } catch {
            print("Permission grant failed: \(error)")
        }
    }
    
    // MARK: - Process with Timeout
    /// Runs a process with a timeout. Returns success status and whether it timed out.
    /// - Parameters:
    ///   - process: The Process to run
    ///   - timeout: Maximum time to wait in seconds (default 60)
    /// - Returns: Tuple containing success (bool) and timedOut (bool)
    private func runProcessWithTimeout(_ process: Process, timeout: TimeInterval = 60) -> (success: Bool, timedOut: Bool) {
        let semaphore = DispatchSemaphore(value: 0)
        
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        
        do {
            try process.run()
        } catch {
            return (false, false)
        }
        
        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        
        if timeoutResult == .timedOut {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            return (false, true)
        }
        
        return (process.terminationStatus == 0, false)
    }
    
    /// Result structure for shell pipeline execution
    private struct ProcessResult {
        var success: Bool
        var timedOut: Bool
        var errorMessage: String?
    }
    
    /// Executes the shell pipeline to convert an image to the target format
    private func executeShellPipeline(sourceURL: URL, targetFormat: TargetFormat) -> ProcessResult {
        // 1. Define and Create Output Directory
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let optimizedDirectory = parentDirectory.appendingPathComponent("Optimized Files")
        
        do {
            if !FileManager.default.fileExists(atPath: optimizedDirectory.path) {
                try FileManager.default.createDirectory(at: optimizedDirectory, withIntermediateDirectories: true, attributes: nil)
            }
        } catch { 
            return ProcessResult(success: false, timedOut: false, errorMessage: "Failed to create output directory") 
        }
        
        // 2. Keep Exact Original Filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        
        if targetFormat == .webp {
            guard let cwebpPath = Bundle.main.path(forResource: "cwebp", ofType: nil) else { 
                return ProcessResult(success: false, timedOut: false, errorMessage: "cwebp binary not found") 
            }
            grantExecutablePermissions(to: cwebpPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("webp")
            let webpQ = UserDefaults.standard.double(forKey: "webpQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "webpQuality")) : 80
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cwebpPath)
            // Upgraded: Added -m 6 (max compression) and -mt (multi-threading)
            process.arguments = ["-q", "\(webpQ)", "-m", "6", "-mt", sourceURL.path, "-o", finalURL.path]
            
            let result = runProcessWithTimeout(process, timeout: processingTimeout)
            if result.timedOut {
                return ProcessResult(success: false, timedOut: true, errorMessage: "WebP conversion timed out")
            }
            let fileExists = FileManager.default.fileExists(atPath: finalURL.path)
            if !fileExists {
                return ProcessResult(success: false, timedOut: false, errorMessage: "WebP file was not created")
            }
            return ProcessResult(success: result.success, timedOut: false, errorMessage: nil)
            
        } else {
            // STEP 1: Lossy Color Quantization (pngquant)
            guard let pngquantPath = Bundle.main.path(forResource: "pngquant", ofType: nil) else { 
                return ProcessResult(success: false, timedOut: false, errorMessage: "pngquant binary not found") 
            }
            grantExecutablePermissions(to: pngquantPath)
            
            let finalURL = optimizedDirectory.appendingPathComponent(originalName).appendingPathExtension("png")
            let pngMax = UserDefaults.standard.double(forKey: "pngQuality") > 0 ? Int(UserDefaults.standard.double(forKey: "pngQuality")) : 80
            let pngMin = max(0, pngMax - 15)
            
            let process1 = Process()
            process1.executableURL = URL(fileURLWithPath: pngquantPath)
            // Upgraded: Added --speed 1 (max effort) and --strip (removes metadata bloat)
            process1.arguments = ["--quality=\(pngMin)-\(pngMax)", "--speed", "1", "--strip", "--force", sourceURL.path, "--output", finalURL.path]
            
            let result1 = runProcessWithTimeout(process1, timeout: processingTimeout)
            if result1.timedOut {
                return ProcessResult(success: false, timedOut: true, errorMessage: "PNG quantization timed out")
            }
            guard result1.success && FileManager.default.fileExists(atPath: finalURL.path) else { 
                return ProcessResult(success: false, timedOut: false, errorMessage: "PNG quantization failed") 
            }
            
            // STEP 2: Lossless Deflation (oxipng)
            // Fails silently and returns the pngquant version if oxipng isn't bundled yet
            guard let oxipngPath = Bundle.main.path(forResource: "oxipng", ofType: nil) else { 
                return ProcessResult(success: true, timedOut: false, errorMessage: nil) 
            }
            grantExecutablePermissions(to: oxipngPath)
            
            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: oxipngPath)
            // -o 4 is optimal max effort. Overwrites the file in-place.
            process2.arguments = ["-o", "4", "--strip", "safe", finalURL.path]
            
            let result2 = runProcessWithTimeout(process2, timeout: processingTimeout)
            if result2.timedOut {
                return ProcessResult(success: true, timedOut: false, errorMessage: nil) // Step 1 still succeeded
            }
            return ProcessResult(success: result2.success, timedOut: false, errorMessage: nil)
        }
    }
}
