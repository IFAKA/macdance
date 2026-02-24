import Metal
import MetalKit
import SwiftUI
import CoreGraphics
import os

// Must match GhostVertex in GhostShaders.metal (32 bytes)
struct GhostVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
    var uv: SIMD2<Float>
}

// Must match GhostUniforms in GhostShaders.metal (16 bytes)
struct GhostUniforms {
    var beatPulse: Float
    var time: Float
    var glowIntensity: Float
    var padding: Float = 0
}

struct GhostRendererConfig: Sendable {
    var ghostColor: SIMD4<Float> = SIMD4(0.4, 0.7, 1.0, 0.7)
    var glowColor: SIMD4<Float> = SIMD4(0.6, 0.85, 1.0, 0.4)
    var missColor: SIMD4<Float> = SIMD4(1.0, 0.2, 0.2, 0.9)
    var particleColor: SIMD4<Float> = SIMD4(1.0, 0.9, 0.3, 0.9)
    var capsuleWidth: Float = 0.018
    var jointRadius: Float = 0.014
}

struct RenderParticle: Sendable {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var color: SIMD4<Float>
}

struct RenderSnapshot: Sendable {
    var pose: PoseFrame?
    var missedJoints: Set<JointName> = []
    var particles: [RenderParticle] = []
    var config: GhostRendererConfig = GhostRendererConfig()
    var beatPulse: Float = 0
    var comboMultiplier: Float = 1.0
    var startTime: ContinuousClock.Instant = .now
}

final class GhostRenderer: Sendable {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let capsulePipeline: MTLRenderPipelineState
    private let jointPipeline: MTLRenderPipelineState
    private let particlePipeline: MTLRenderPipelineState

    let snapshot: OSAllocatedUnfairLock<RenderSnapshot>

    static let boneConnections: [(JointName, JointName)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.nose, .leftShoulder), (.nose, .rightShoulder)
    ]

    static let jointCircleSegments = 16

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.snapshot = OSAllocatedUnfairLock(initialState: RenderSnapshot())

        // Try default library first, then inline shaders as fallback
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            let src = """
            #include <metal_stdlib>
            using namespace metal;
            struct GhostVertex { float2 position; float4 color; float2 uv; };
            struct VertexOut { float4 position [[position]]; float4 color; float2 uv; };
            struct GhostUniforms { float beatPulse; float time; float glowIntensity; float padding; };
            vertex VertexOut ghost_vertex(uint vid [[vertex_id]], constant GhostVertex* v [[buffer(0)]], constant GhostUniforms& u [[buffer(1)]]) {
                VertexOut out; out.position = float4(v[vid].position, 0, 1); out.color = v[vid].color; out.uv = v[vid].uv; return out;
            }
            fragment float4 ghost_fragment(VertexOut in [[stage_in]], constant GhostUniforms& u [[buffer(1)]]) {
                float dist = abs(in.uv.x); float a = smoothstep(1.0, 0.3, dist);
                float glow = u.glowIntensity;
                float3 baseGlow = mix(float3(0.6,0.85,1.0), float3(1.0,0.85,0.1), saturate((glow - 1.0) * 2.0));
                float3 c = in.color.rgb * a + baseGlow * (1.0 - dist) * 0.3 * glow * (1.0 + u.beatPulse * 0.4);
                return float4(c, in.color.a * a);
            }
            vertex VertexOut joint_vertex(uint vid [[vertex_id]], constant GhostVertex* v [[buffer(0)]], constant GhostUniforms& u [[buffer(1)]]) {
                VertexOut out; out.position = float4(v[vid].position, 0, 1); out.color = v[vid].color; out.uv = v[vid].uv; return out;
            }
            fragment float4 joint_fragment(VertexOut in [[stage_in]], constant GhostUniforms& u [[buffer(1)]]) {
                float dist = length(in.uv); float a = smoothstep(1.0, 0.5, dist);
                return float4(in.color.rgb * a, in.color.a * a);
            }
            vertex VertexOut particle_vertex(uint vid [[vertex_id]], constant GhostVertex* v [[buffer(0)]], constant GhostUniforms& u [[buffer(1)]]) {
                VertexOut out; out.position = float4(v[vid].position, 0, 1); out.color = v[vid].color; out.uv = v[vid].uv; return out;
            }
            fragment float4 particle_fragment(VertexOut in [[stage_in]], constant GhostUniforms& u [[buffer(1)]]) {
                float dist = length(in.uv); float a = smoothstep(1.0, 0.0, dist) * in.color.a;
                return float4(in.color.rgb * (1.0 + (1.0-dist)*0.5), a);
            }
            """
            guard let inlineLib = try? device.makeLibrary(source: src, options: nil) else { return nil }
            library = inlineLib
        }

        func makePipeline(vertex: String, fragment: String, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
            guard let vf = library.makeFunction(name: vertex),
                  let ff = library.makeFunction(name: fragment) else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vf
            desc.fragmentFunction = ff
            desc.colorAttachments[0].pixelFormat = pixelFormat
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        let fmt = MTLPixelFormat.bgra8Unorm
        guard let capsule = makePipeline(vertex: "ghost_vertex", fragment: "ghost_fragment", pixelFormat: fmt),
              let joint = makePipeline(vertex: "joint_vertex", fragment: "joint_fragment", pixelFormat: fmt),
              let particle = makePipeline(vertex: "particle_vertex", fragment: "particle_fragment", pixelFormat: fmt)
        else { return nil }

        self.capsulePipeline = capsule
        self.jointPipeline = joint
        self.particlePipeline = particle
    }

    func configureView(_ view: MTKView, delegate: GhostRendererDelegate) {
        view.device = device
        view.delegate = delegate
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
    }

    // MARK: - State updates (called from MainActor)

    func updatePose(_ pose: PoseFrame?) {
        snapshot.withLock { $0.pose = pose }
    }

    func updateMissedJoints(_ joints: Set<JointName>) {
        snapshot.withLock { $0.missedJoints = joints }
    }

    func updateConfig(_ config: GhostRendererConfig) {
        snapshot.withLock { $0.config = config }
    }

    func setBeatPulse(_ pulse: Float) {
        snapshot.withLock { $0.beatPulse = pulse }
    }

    func setComboMultiplier(_ multiplier: Float) {
        snapshot.withLock { $0.comboMultiplier = multiplier }
    }

    func addParticles(at position: SIMD2<Float>, color: SIMD4<Float>, count: Int = 8) {
        snapshot.withLock { state in
            for _ in 0..<count {
                let angle = Float.random(in: 0..<(.pi * 2))
                let speed = Float.random(in: 0.01...0.05)
                state.particles.append(RenderParticle(
                    position: position,
                    velocity: SIMD2(cos(angle) * speed, sin(angle) * speed),
                    life: 1.0,
                    color: color
                ))
            }
        }
    }

    func triggerBurst(at joints: [JointName], particlesPerJoint: Int = 8) {
        snapshot.withLock { state in
            guard let pose = state.pose else { return }
            for joint in joints {
                guard let pt = pose.joint(joint) else { continue }
                let pos = SIMD2<Float>(Float(pt.x) * 2 - 1, Float(1 - pt.y) * 2 - 1)
                for _ in 0..<particlesPerJoint {
                    let angle = Float.random(in: 0..<(.pi * 2))
                    let speed = Float.random(in: 0.01...0.05)
                    state.particles.append(RenderParticle(
                        position: pos,
                        velocity: SIMD2(cos(angle) * speed, sin(angle) * speed),
                        life: 1.0,
                        color: state.config.particleColor
                    ))
                }
            }
        }
    }

    func flashMissed(_ joints: [JointName]) {
        snapshot.withLock { $0.missedJoints = Set(joints) }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            self.snapshot.withLock { $0.missedJoints = [] }
        }
    }

    func pulseBeat() {
        snapshot.withLock { $0.beatPulse = 1.0 }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            self.snapshot.withLock { $0.beatPulse = 0 }
        }
    }

    func draw(in view: MTKView) {
        // Take snapshot and update particles atomically
        let state = snapshot.withLock { state -> RenderSnapshot in
            let dt: Float = 1.0 / 60.0
            state.particles = state.particles.compactMap { p in
                var p = p
                p.position += p.velocity * dt * 60.0
                p.life -= dt * 1.5
                p.velocity.y -= 0.0005 // slight gravity
                return p.life > 0 ? p : nil
            }
            return state
        }

        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        let elapsed = Float(state.startTime.duration(to: .now).components.seconds)
            + Float(state.startTime.duration(to: .now).components.attoseconds) * 1e-18
        let comboGlow = 1.0 + (state.comboMultiplier - 1.0) * 0.5
        var uniforms = GhostUniforms(
            beatPulse: state.beatPulse,
            time: elapsed,
            glowIntensity: comboGlow
        )

        // Draw capsule bones
        if let pose = state.pose {
            let capsuleVerts = generateCapsuleVertices(
                pose: pose,
                missedJoints: state.missedJoints,
                config: state.config
            )
            if !capsuleVerts.isEmpty {
                encoder.setRenderPipelineState(capsulePipeline)
                let buf = device.makeBuffer(
                    bytes: capsuleVerts,
                    length: capsuleVerts.count * MemoryLayout<GhostVertex>.stride,
                    options: .storageModeShared
                )
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: capsuleVerts.count)
            }

            // Draw joint circles
            let jointVerts = generateJointVertices(
                pose: pose,
                missedJoints: state.missedJoints,
                config: state.config
            )
            if !jointVerts.isEmpty {
                encoder.setRenderPipelineState(jointPipeline)
                let buf = device.makeBuffer(
                    bytes: jointVerts,
                    length: jointVerts.count * MemoryLayout<GhostVertex>.stride,
                    options: .storageModeShared
                )
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: jointVerts.count)
            }
        }

        // Draw particles
        if !state.particles.isEmpty {
            let particleVerts = generateParticleVertices(particles: state.particles)
            encoder.setRenderPipelineState(particlePipeline)
            let buf = device.makeBuffer(
                bytes: particleVerts,
                length: particleVerts.count * MemoryLayout<GhostVertex>.stride,
                options: .storageModeShared
            )
            encoder.setVertexBuffer(buf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GhostUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: particleVerts.count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Geometry generation

    private func generateCapsuleVertices(
        pose: PoseFrame,
        missedJoints: Set<JointName>,
        config: GhostRendererConfig
    ) -> [GhostVertex] {
        var verts: [GhostVertex] = []
        verts.reserveCapacity(Self.boneConnections.count * 6)

        for (a, b) in Self.boneConnections {
            guard let pa = pose.joint(a), let pb = pose.joint(b) else { continue }
            let missed = missedJoints.contains(b) || missedJoints.contains(a)
            let color = missed ? config.missColor : config.ghostColor

            let ax = Float(pa.x) * 2.0 - 1.0
            let ay = Float(1.0 - pa.y) * 2.0 - 1.0
            let bx = Float(pb.x) * 2.0 - 1.0
            let by = Float(1.0 - pb.y) * 2.0 - 1.0

            let dx = bx - ax
            let dy = by - ay
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0.001 else { continue }

            // Perpendicular direction for capsule width
            let nx = -dy / len * config.capsuleWidth
            let ny = dx / len * config.capsuleWidth

            // Quad: two triangles
            let p0 = SIMD2<Float>(ax + nx, ay + ny)
            let p1 = SIMD2<Float>(ax - nx, ay - ny)
            let p2 = SIMD2<Float>(bx + nx, by + ny)
            let p3 = SIMD2<Float>(bx - nx, by - ny)

            // Triangle 1: p0, p1, p2
            verts.append(GhostVertex(position: p0, color: color, uv: SIMD2(-1, 0)))
            verts.append(GhostVertex(position: p1, color: color, uv: SIMD2(1, 0)))
            verts.append(GhostVertex(position: p2, color: color, uv: SIMD2(-1, 1)))
            // Triangle 2: p1, p3, p2
            verts.append(GhostVertex(position: p1, color: color, uv: SIMD2(1, 0)))
            verts.append(GhostVertex(position: p3, color: color, uv: SIMD2(1, 1)))
            verts.append(GhostVertex(position: p2, color: color, uv: SIMD2(-1, 1)))

            // Add rounded caps (semicircles at each end)
            let capSegments = 6
            for i in 0..<capSegments {
                let a0 = Float.pi * 0.5 + Float(i) * Float.pi / Float(capSegments)
                let a1 = Float.pi * 0.5 + Float(i + 1) * Float.pi / Float(capSegments)

                // Cap at start (A)
                let dirAx = -dx / len
                let dirAy = -dy / len
                let c0x = ax + cos(a0) * nx + sin(a0) * dirAx * config.capsuleWidth
                let c0y = ay + cos(a0) * ny + sin(a0) * dirAy * config.capsuleWidth
                let c1x = ax + cos(a1) * nx + sin(a1) * dirAx * config.capsuleWidth
                let c1y = ay + cos(a1) * ny + sin(a1) * dirAy * config.capsuleWidth

                verts.append(GhostVertex(position: SIMD2(ax, ay), color: color, uv: SIMD2(0, 0)))
                verts.append(GhostVertex(position: SIMD2(c0x, c0y), color: color, uv: SIMD2(cos(a0), sin(a0))))
                verts.append(GhostVertex(position: SIMD2(c1x, c1y), color: color, uv: SIMD2(cos(a1), sin(a1))))

                // Cap at end (B)
                let rA0 = a0 + Float.pi
                let rA1 = a1 + Float.pi
                let d0x = bx + cos(rA0) * nx + sin(rA0) * (-dirAx) * config.capsuleWidth
                let d0y = by + cos(rA0) * ny + sin(rA0) * (-dirAy) * config.capsuleWidth
                let d1x = bx + cos(rA1) * nx + sin(rA1) * (-dirAx) * config.capsuleWidth
                let d1y = by + cos(rA1) * ny + sin(rA1) * (-dirAy) * config.capsuleWidth

                verts.append(GhostVertex(position: SIMD2(bx, by), color: color, uv: SIMD2(0, 0)))
                verts.append(GhostVertex(position: SIMD2(d0x, d0y), color: color, uv: SIMD2(cos(rA0), sin(rA0))))
                verts.append(GhostVertex(position: SIMD2(d1x, d1y), color: color, uv: SIMD2(cos(rA1), sin(rA1))))
            }
        }
        return verts
    }

    private func generateJointVertices(
        pose: PoseFrame,
        missedJoints: Set<JointName>,
        config: GhostRendererConfig
    ) -> [GhostVertex] {
        var verts: [GhostVertex] = []
        let segments = Self.jointCircleSegments

        for joint in JointName.allCases {
            guard let pt = pose.joint(joint) else { continue }
            let missed = missedJoints.contains(joint)
            let color = missed ? config.missColor : config.ghostColor

            let cx = Float(pt.x) * 2.0 - 1.0
            let cy = Float(1.0 - pt.y) * 2.0 - 1.0
            let r = config.jointRadius

            for i in 0..<segments {
                let a0 = Float(i) * (2.0 * .pi / Float(segments))
                let a1 = Float(i + 1) * (2.0 * .pi / Float(segments))

                verts.append(GhostVertex(position: SIMD2(cx, cy), color: color, uv: SIMD2(0, 0)))
                verts.append(GhostVertex(
                    position: SIMD2(cx + cos(a0) * r, cy + sin(a0) * r),
                    color: color,
                    uv: SIMD2(cos(a0), sin(a0))
                ))
                verts.append(GhostVertex(
                    position: SIMD2(cx + cos(a1) * r, cy + sin(a1) * r),
                    color: color,
                    uv: SIMD2(cos(a1), sin(a1))
                ))
            }
        }
        return verts
    }

    private func generateParticleVertices(particles: [RenderParticle]) -> [GhostVertex] {
        var verts: [GhostVertex] = []
        verts.reserveCapacity(particles.count * 6)
        let particleSize: Float = 0.008

        for p in particles {
            var color = p.color
            color.w *= p.life

            let cx = p.position.x
            let cy = p.position.y
            let s = particleSize * p.life

            // Quad as 2 triangles
            verts.append(GhostVertex(position: SIMD2(cx - s, cy - s), color: color, uv: SIMD2(-1, -1)))
            verts.append(GhostVertex(position: SIMD2(cx + s, cy - s), color: color, uv: SIMD2(1, -1)))
            verts.append(GhostVertex(position: SIMD2(cx - s, cy + s), color: color, uv: SIMD2(-1, 1)))

            verts.append(GhostVertex(position: SIMD2(cx + s, cy - s), color: color, uv: SIMD2(1, -1)))
            verts.append(GhostVertex(position: SIMD2(cx + s, cy + s), color: color, uv: SIMD2(1, 1)))
            verts.append(GhostVertex(position: SIMD2(cx - s, cy + s), color: color, uv: SIMD2(-1, 1)))
        }
        return verts
    }
}

// Separate NSObject delegate for MTKViewDelegate protocol conformance
final class GhostRendererDelegate: NSObject, MTKViewDelegate {
    let renderer: GhostRenderer

    init(renderer: GhostRenderer) {
        self.renderer = renderer
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        renderer.draw(in: view)
    }
}
