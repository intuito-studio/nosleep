// Ported from Mac Duo (github.com/ninobc/mac-duo): DuoRenderer and DuoShaders.
// Copyright (c) 2026 Nino Bouchedid. MIT License; see THIRD-PARTY-NOTICES.md.

import AppKit
import Metal
import MetalPerformanceShaders
import NoSleepCore
import QuartzCore
import simd

/// Draws the fold with Metal: the frozen picture of the built-in display,
/// re-projected through the tilting glass, frosted and darkened from the far
/// edge, in one full-screen pass. The picture is one mipmapped texture with a
/// Gaussian pyramid over it, so the blur is a tent of trilinear samples at a
/// level chosen per pixel.
@MainActor
final class FoldRenderer {
    let layer = CAMetalLayer()
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var picture: MTLTexture?
    private var maxLevel: Float = 0

    var hasPicture: Bool { picture != nil }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaders, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
        layer.device = device
        layer.pixelFormat = .bgra8Unorm_srgb
        layer.framebufferOnly = true
        // An opaque full-screen layer makes the window server treat everything
        // underneath as hidden, and apps stop drawing. The shader writes alpha
        // 1 everywhere, so blending gives the same picture.
        layer.isOpaque = false
        layer.colorspace = CGColorSpace(name: Self.colourSpace)
    }

    /// Display P3 shares sRGB's transfer curve, so an sRGB texture view decodes it.
    nonisolated static let colourSpace = CGColorSpace.displayP3

    // MARK: - The picture

    /// Freezes one frame from the capture stream. The stream's buffer is
    /// recycled, so the frame is copied into a texture of our own.
    func freeze(_ frame: MTLTexture) {
        guard let target = makePictureTexture(width: frame.width, height: frame.height),
              let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: frame, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: frame.width, height: frame.height, depth: 1),
                  to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        finish(target, commands: commands)
    }

    /// Freezes a still image, for the debug picture.
    func freeze(_ image: CGImage, pixelSize: CGSize) {
        let width = Int(pixelSize.width), height = Int(pixelSize.height)
        let bytesPerRow = width * 4
        guard width > 0, height > 0,
              let staging = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let space = CGColorSpace(name: Self.colourSpace),
              let context = CGContext(data: staging.contents(), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let target = makePictureTexture(width: width, height: height),
              let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { return }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: target, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        finish(target, commands: commands)
    }

    func release() {
        picture = nil
    }

    private func makePictureTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    private func finish(_ texture: MTLTexture, commands: MTLCommandBuffer) {
        var texture = texture
        MPSImageGaussianPyramid(device: device, centerWeight: 0.375)
            .encode(commandBuffer: commands, inPlaceTexture: &texture, fallbackCopyAllocator: nil)
        commands.commit()
        picture = texture
        maxLevel = Float(texture.mipmapLevelCount - 1)
    }

    // MARK: - A frame

    private struct Uniforms {
        var column0: SIMD4<Float>
        var column1: SIMD4<Float>
        var column2: SIMD4<Float>
        var screen: SIMD4<Float>   // size (pt), pixel scale, top edge (pt)
        var look: SIMD4<Float>     // blur strength, max radius (px), dim strength, darkness
        var extra: SIMD4<Float>    // max mip level, grain seed
    }

    /// One frame with the lid at `angle`, for a screen `size` points across at `scale`.
    func render(angle: Double, size: CGSize, scale: CGFloat) {
        guard let picture, size.width > 0, size.height > 0 else { return }
        let drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        if layer.drawableSize != drawableSize { layer.drawableSize = drawableSize }
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }

        let width = Double(size.width), height = Double(size.height)
        let corners = FoldGeometry(screenWidth: width, screenHeight: height, startAngle: LidCurves.fold.startAngle)
            .corners(at: angle)
        let inverse = Homography.matrix(width: width, height: height, to: corners).inverse
        func column(_ i: Int) -> SIMD4<Float> { SIMD4(Float(inverse[i].x), Float(inverse[i].y), Float(inverse[i].z), 0) }
        let progress = LidCurves.foldProgress(at: angle)
        var uniforms = Uniforms(
            column0: column(0), column1: column(1), column2: column(2),
            screen: SIMD4(Float(width), Float(height), Float(scale), Float(min(corners[2].y, corners[3].y, height))),
            look: SIMD4(Float(LidCurves.fold.blurStrength(progress: progress)), Float(125 * scale),
                        Float(LidCurves.fold.dimStrength(progress: progress)), Float(LidCurves.darkness(at: angle))),
            extra: SIMD4(maxLevel, Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100)), 0, 0)
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(picture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    // Every glass pixel maps back into the frozen picture through the inverse
    // perspective. Frost and darkness follow the picture's own height above
    // the hinge, so the far edge dissolves first and the hinge stays sharp.
    private static let shaders = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 column0;
        float4 column1;
        float4 column2;
        float4 screen;
        float4 look;
        float4 extra;
    };

    vertex float4 foldVertex(uint id [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[id], 0.0, 1.0);
    }

    static inline float hash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    fragment float4 foldFragment(float4 position [[position]],
                                 constant Uniforms &u [[buffer(0)]],
                                 texture2d<float> picture [[texture(0)]]) {
        constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);
        const float2 size = u.screen.xy;
        const float scale = u.screen.z;
        const float topEdge = u.screen.w;
        const float blurStrength = u.look.x;
        const float maxRadius = u.look.y;
        const float dimStrength = u.look.z;
        const float darkness = u.look.w;
        const float maxLevel = u.extra.x;

        // Fragments are pixels with y down; the geometry is points with y up.
        float2 p = float2(position.x / scale, size.y - position.y / scale);
        // Rows above the picture's far edge carry that edge's light, fading
        // out, so there is never a line where the picture ends.
        float above = max(p.y - topEdge, 0.0);
        float3x3 toPicture = float3x3(u.column0.xyz, u.column1.xyz, u.column2.xyz);
        float3 m = toPicture * float3(p.x, min(p.y, topEdge), 1.0);
        if (m.z <= 1e-6) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 q = m.xy / m.z;
        float2 qc = clamp(q, float2(0.0), size);
        // Past the picture's sides, as they draw in, its light leaks into the dark.
        float outside = length(q - qc) / size.y;
        float2 uv = float2(qc.x / size.x, 1.0 - qc.y / size.y);

        // Height above the hinge in the picture: 0 at the hinge, 1 at the far edge.
        float g = qc.y / size.y;
        float radius = blurStrength * g * maxRadius;
        float3 colour;
        if (radius < 0.75) {
            colour = picture.sample(smooth, uv, level(0.0)).rgb;
        } else {
            // A 3×3 tent of trilinear taps hides the pyramid's steps.
            float mip = clamp(log2(radius), 0.0, maxLevel);
            float2 stride = radius * 0.45 / (size * scale);
            const float weights[3] = { 1.0, 2.0, 1.0 };
            colour = float3(0.0);
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float w = weights[x + 1] * weights[y + 1] / 16.0;
                    colour += picture.sample(smooth, uv + float2(x, y) * stride, level(mip)).rgb * w;
                }
            }
        }
        // Dimming in linear light, so the far edge fades into the dark rather
        // than going grey; the hinge sinks a little too.
        float dim = dimStrength * (0.18 + 0.82 * smoothstep(0.0, 0.55, g));
        colour *= pow(1.0 - dim, 2.1);
        colour *= exp(-pow(above / (0.22 * size.y), 1.4)) * exp(-pow(outside / 0.05, 1.3));
        // And at the very end, dark, the far edge first.
        float height = p.y / size.y;
        colour *= 1.0 - smoothstep(0.0, 1.0, darkness * (1.3 + (height - 0.5) * 0.6));
        // Grain, so the dark gradient does not band.
        colour += (hash(position.xy + u.extra.y) - 0.5) * (2.5 / 255.0) * dimStrength;
        return float4(max(colour, 0.0), 1.0);
    }
    """
}
