import CoreMedia
import CoreVideo

class PiPVideoMixer {
    
    var description = "Video Mixer"
    
    private(set) var isPrepared = false
    
    private(set) var inputFormatDescription: CMFormatDescription?
    
    var outputFormatDescription: CMFormatDescription?
    
    private var outputPixelBufferPool: CVPixelBufferPool?
    
    private let metalDevice = MTLCreateSystemDefaultDevice()
    private var textureCache: CVMetalTextureCache?
    
    private lazy var commandQueue: MTLCommandQueue? = {
        guard let metalDevice = metalDevice else {
            return nil
        }
        
        return metalDevice.makeCommandQueue()
    }()
    
    private var fullRangeVertexBuffer: MTLBuffer?
    private var computePipelineState: MTLComputePipelineState?
    
    init() {
        guard let metalDevice = metalDevice,
              let defaultLibrary = metalDevice.makeDefaultLibrary(),
              let kernelFunction = defaultLibrary.makeFunction(name: "splitScreenMixer") else {
            return
        }
        
        do {
            computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Could not create compute pipeline state: \(error)")
        }
    }
    
    func prepare(with videoFormatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
        reset()
        
        (outputPixelBufferPool, _, outputFormatDescription) = allocateOutputBufferPool(with: videoFormatDescription,
                                                                                       outputRetainedBufferCountHint: outputRetainedBufferCountHint)
        if outputPixelBufferPool == nil {
            return
        }
        inputFormatDescription = videoFormatDescription
        
        guard let metalDevice = metalDevice else {
            return
        }
        
        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            assertionFailure("Unable to allocate video mixer texture cache")
        } else {
            textureCache = metalTextureCache
        }
        
        isPrepared = true
    }
    
    func reset() {
        outputPixelBufferPool = nil
        outputFormatDescription = nil
        inputFormatDescription = nil
        textureCache = nil
        isPrepared = false
    }
    
    struct MixerParameters {
        var leftPosition: SIMD2<Float>
        var leftSize: SIMD2<Float>
        var rightPosition: SIMD2<Float>
        var rightSize: SIMD2<Float>
    }
    
    func mix(leftPixelBuffer: CVPixelBuffer, rightPixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard isPrepared,
              let outputPixelBufferPool = outputPixelBufferPool else {
            assertionFailure("Invalid state: Not prepared")
            return nil
        }
        
        var newPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("Allocation failure: Could not get pixel buffer from pool (\(self.description))")
            return nil
        }
        
        guard let outputTexture = makeTextureFromCVPixelBuffer(pixelBuffer: outputPixelBuffer),
              let leftTexture = makeTextureFromCVPixelBuffer(pixelBuffer: leftPixelBuffer),
              let rightTexture = makeTextureFromCVPixelBuffer(pixelBuffer: rightPixelBuffer) else {
            return nil
        }
        
        let leftPosition = SIMD2<Float>(0, 0)
        let leftSize = SIMD2<Float>(Float(leftTexture.width) / 2, Float(leftTexture.height))
        let rightPosition = SIMD2<Float>(Float(leftTexture.width) / 2, 0)
        let rightSize = SIMD2<Float>(Float(rightTexture.width) / 2, Float(rightTexture.height))
        
        var parameters = MixerParameters(leftPosition: leftPosition, leftSize: leftSize, rightPosition: rightPosition, rightSize: rightSize)
        
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let commandEncoder = commandBuffer.makeComputeCommandEncoder(),
              let computePipelineState = computePipelineState else {
            print("Failed to create Metal command encoder")
            
            if let textureCache = textureCache {
                CVMetalTextureCacheFlush(textureCache, 0)
            }
            
            return nil
        }
        
        commandEncoder.label = "Split Screen Video Mixer"
        commandEncoder.setComputePipelineState(computePipelineState)
        commandEncoder.setTexture(leftTexture, index: 0)
        commandEncoder.setTexture(rightTexture, index: 1)
        commandEncoder.setTexture(outputTexture, index: 2)
        withUnsafeMutablePointer(to: &parameters) { parametersRawPointer in
            commandEncoder.setBytes(parametersRawPointer, length: MemoryLayout<MixerParameters>.size, index: 0)
        }
        
        let width = computePipelineState.threadExecutionWidth
        let height = computePipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
        let threadgroupsPerGrid = MTLSize(width: (leftTexture.width + width - 1) / width,
                                          height: (leftTexture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        return outputPixelBuffer
    }
    
    private func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else {
            print("No texture cache")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            print("Video mixer failed to create preview texture")
            
            CVMetalTextureCacheFlush(textureCache, 0)
            return nil
        }
        
        return texture
    }
}
