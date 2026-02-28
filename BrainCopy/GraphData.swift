import Foundation
import simd

struct GraphData: Codable {
    var nodes: [GraphNodeData]
    var edges: [GraphEdgeData]
}

struct GraphNodeData: Codable, Identifiable {
    let id: Int
    let x: Float
    let y: Float
    let z: Float?
    let label: String?
    let cluster: Int?

    func position(scale: Float, depthRange: ClosedRange<Float>) -> SIMD3<Float> {
        let depth = z ?? Float.random(in: depthRange)
        return SIMD3<Float>(x * scale, y * scale, depth * scale)
    }
}

struct GraphEdgeData: Codable, Hashable {
    let source: Int
    let target: Int
}
