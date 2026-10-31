import AppKit
import Metal
import NoSleepCore
import QuartzCore

/// Draws the eyes' light flooding the screen, in its own clear layer over
/// everything else in the overlay: the desktop, the fold and the glass cat.
/// It needs no picture of the screen, so it runs with the fold switched off.
@MainActor
final class FloodRenderer {
    let layer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: Self.shaders, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "floodVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "floodFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
        layer.device = device
        // Not _srgb: the window server blends a layer in its encoded values,
        // so the shader encodes the colour itself and premultiplies after.
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        // Clear where the flood has not reached; opaque would also stop the
        // window server drawing the apps underneath.
        layer.isOpaque = false
        // The site's colours are linear sRGB, as WebGL's are.
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    private struct Uniforms {
        var screen: SIMD4<Float>   // size (pt), pixel scale, flood
        var eyes: SIMD4<Float>     // both eye centres (pt, y down)
    }

    /// One frame of the flood at `flood` (`LidCurves.flood`), for eyes at
    /// `eyes` on a screen `size` points across at `scale`.
    func render(flood: Double, eyes: [CGPoint], size: CGSize, scale: CGFloat) {
        guard eyes.count == 2, size.width > 0, size.height > 0 else { return }
        let drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
        if layer.drawableSize != drawableSize { layer.drawableSize = drawableSize }
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        var uniforms = Uniforms(
            screen: SIMD4(Float(size.width), Float(size.height), Float(scale), Float(flood)),
            eyes: SIMD4(Float(eyes[0].x), Float(eyes[0].y), Float(eyes[1].x), Float(eyes[1].y))
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    // LidCurves.floodCover and floodColour, per pixel; the home page's
    // frost shader (site/lib/laptop-scene.ts) draws the same. Change all three.
    private static let shaders = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 screen;
        float4 eyes;
    };

    vertex float4 floodVertex(uint id [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[id], 0.0, 1.0);
    }

    static inline float3 encode(float3 c) {
        return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
    }

    fragment float4 floodFragment(float4 position [[position]],
                                  constant Uniforms &u [[buffer(0)]]) {
        const float height = u.screen.y;
        const float flood = u.screen.w;
        // Points, y down, as the eye centres; distances in screen heights.
        float2 p = position.xy / u.screen.z;
        float d = min(length(p - u.eyes.xy), length(p - u.eyes.zw)) / height;
        float r = mix(0.05, 2.3, flood);
        float cover = 1.0 - smoothstep(r * 0.45, r, d);
        float3 warm = mix(float3(1.0, 0.46, 0.03), float3(1.0, 0.14, 0.0), smoothstep(0.0, 1.4, d));
        return float4(encode(warm) * cover, cover);
    }
    """
}
