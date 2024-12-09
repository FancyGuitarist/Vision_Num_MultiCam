/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Records movies using AVAssetWriter.
*/

import Foundation
import AVFoundation
import CoreMotion
import UIKit

class MovieRecorder {
	
	private var assetWriter: AVAssetWriter?
	
	private var assetWriterVideoInput: AVAssetWriterInput?
	
	private var assetWriterAudioInput: AVAssetWriterInput?
	
	private var videoTransform: CGAffineTransform
	
	private var videoSettings: [String: Any]

	private var audioSettings: [String: Any]
    
    private let motionManager = CMMotionManager()

	private(set) var isRecording = false
	
	init(audioSettings: [String: Any], videoSettings: [String: Any], videoTransform: CGAffineTransform) {
		self.audioSettings = audioSettings
		self.videoSettings = videoSettings
		self.videoTransform = videoTransform
	}
    
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
	
	func startRecording() {
		// Create an asset writer that records to a temporary file
		let outputFileName = NSUUID().uuidString
		let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("MOV")
		guard let assetWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mov) else {
			return
		}
		
		// Add an audio input
		let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
		assetWriterAudioInput.expectsMediaDataInRealTime = true
		assetWriter.add(assetWriterAudioInput)
		
		// Add a video input
		let assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
		assetWriterVideoInput.expectsMediaDataInRealTime = true
		assetWriterVideoInput.transform = videoTransform
		assetWriter.add(assetWriterVideoInput)
		
		self.assetWriter = assetWriter
		self.assetWriterAudioInput = assetWriterAudioInput
		self.assetWriterVideoInput = assetWriterVideoInput
        
        // Create a pixel buffer adaptor
        let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterVideoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes)

        // Start motion updates
        motionManager.startAccelerometerUpdates()
        motionManager.startGyroUpdates()
		
		isRecording = true
	}
	
	func stopRecording(completion: @escaping (URL) -> Void) {
		guard let assetWriter = assetWriter else {
			return
		}
		
		self.isRecording = false
		self.assetWriter = nil
		
		assetWriter.finishWriting {
			completion(assetWriter.outputURL)
		}
	}
    
    func createWatermarkLayer(accelX: Double, accelY: Double, accelZ: Double, gyroX: Double, gyroY: Double, gyroZ: Double) -> CALayer {
        let watermarkLayer = CATextLayer()
        let rounded_accelX = String(format: "%.4f", accelX)
        let rounded_accelY = String(format: "%.4f", accelY)
        let rounded_accelZ = String(format: "%.4f", accelZ)
        let rounded_gyroX = String(format: "%.4f", gyroX)
        let rounded_gyroY = String(format: "%.4f", gyroY)
        let rounded_gyroZ = String(format: "%.4f", gyroZ)
        
        watermarkLayer.string = """
        Accel: (X: \(rounded_accelX), Y: \(rounded_accelY), Z: \(rounded_accelZ))
        Gyro: (X: \(rounded_gyroX), Y: \(rounded_gyroY), Z: \(rounded_gyroZ))
        """
        watermarkLayer.foregroundColor = UIColor.red.cgColor
        watermarkLayer.fontSize = 24
        watermarkLayer.alignmentMode = .left
        watermarkLayer.contentsScale = UIScreen.main.scale
        watermarkLayer.frame = CGRect(x: 10, y: 10, width: 800, height: 100)
        // Apply a vertical flip transformation to the watermark layer
        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, .pi, 1.0, 0.0, 0.0)
        watermarkLayer.transform = transform

        print("Watermark Layer Frame: \(watermarkLayer.frame)")
        
        return watermarkLayer
    }

    
    func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    func addWatermarkToFrame(sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)

        // Get the motion data
        guard let accelerometerData = motionManager.accelerometerData,
              let gyroData = motionManager.gyroData else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            return imageBuffer
        }

        let accelX = accelerometerData.acceleration.x
        let accelY = accelerometerData.acceleration.y
        let accelZ = accelerometerData.acceleration.z
        let gyroX = gyroData.rotationRate.x
        let gyroY = gyroData.rotationRate.y
        let gyroZ = gyroData.rotationRate.z

        // Create a watermark layer with the transformation applied
        let watermarkLayer = createWatermarkLayer(accelX: accelX, accelY: accelY, accelZ: accelZ, gyroX: gyroX, gyroY: gyroY, gyroZ: gyroZ)

        // Create a new pixel buffer
        var newPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(imageBuffer),
            CVPixelBufferGetHeight(imageBuffer),
            kCVPixelFormatType_32ARGB,
            nil,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputPixelBuffer = newPixelBuffer else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            return imageBuffer
        }

        // Create a CGImage from the pixel buffer
        guard let cgImage = createCGImage(from: imageBuffer) else {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            return imageBuffer
        }

        // Render the watermark layer onto the new pixel buffer
        CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(outputPixelBuffer),
            width: CVPixelBufferGetWidth(outputPixelBuffer),
            height: CVPixelBufferGetHeight(outputPixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(outputPixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )

        if let context = context {
            // Draw the original image buffer into the context
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(outputPixelBuffer), height: CVPixelBufferGetHeight(outputPixelBuffer)))
            // Render the watermark layer into the context
            watermarkLayer.render(in: context)
        }

        CVPixelBufferUnlockBaseAddress(outputPixelBuffer, [])
        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)

        return outputPixelBuffer
    }
	
    func recordVideo(sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let assetWriter = assetWriter,
              let pixelBufferAdaptor = pixelBufferAdaptor else {
            return
        }

        if assetWriter.status == .unknown {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        } else if assetWriter.status == .writing {
            if let input = assetWriterVideoInput,
               input.isReadyForMoreMediaData {
                
                // Add watermark to the frame
                if let watermarkedBuffer = addWatermarkToFrame(sampleBuffer: sampleBuffer) {
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    pixelBufferAdaptor.append(watermarkedBuffer, withPresentationTime: presentationTime)
                }
            }
        }
    }
	
	func recordAudio(sampleBuffer: CMSampleBuffer) {
		guard isRecording,
			let assetWriter = assetWriter,
			assetWriter.status == .writing,
			let input = assetWriterAudioInput,
			input.isReadyForMoreMediaData else {
				return
		}
		
		input.append(sampleBuffer)
	}
}
