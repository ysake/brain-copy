//
//  ContentView.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI
import UIKit
import RealityKit
import simd

struct ContentView: View {

    @State private var graphCoordinator = NetworkGraphCoordinator()

    var body: some View {
        RealityView { content in
            graphCoordinator.configureIfNeeded(content: &content)
        }
    }
}

private final class NetworkGraphCoordinator {

    private let simulation = NetworkGraphSimulation()
    private let renderer = NetworkGraphRenderer()
    private var updateSubscription: EventSubscription?
    private var isConfigured = false
    private let graphData = GraphDataLoader.loadDefaultGraphData()

    func configureIfNeeded<Content: RealityViewContentProtocol>(content: inout Content) {
        guard !isConfigured else { return }
        isConfigured = true

        simulation.configure(graphData: graphData)
        renderer.build(content: &content, nodes: simulation.nodes, edges: simulation.edges)

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.step(deltaTime: Float(event.deltaTime))
        }
    }

    private func step(deltaTime: Float) {
        simulation.step(deltaTime: deltaTime)
        renderer.update(nodes: simulation.nodes)
    }
}

private struct NetworkNode {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var radius: Float
    var color: UIColor
}

private struct NetworkEdge {
    let a: Int
    let b: Int
    let restLength: Float
}

private final class NetworkGraphSimulation {

    private(set) var nodes: [NetworkNode] = []
    private(set) var edges: [NetworkEdge] = []

    private let defaultNodeCount = 430
    private let baseNodeRadius: Float = 0.035
    private let initialRadius: Float = 0.65
    private let springStrength: Float = 2.0
    private let springRestLength: Float = 0.23
    private let repulsionStrength: Float = 0.018
    private let damping: Float = 0.9
    private let maxSpeed: Float = 1.1
    private let fixedTimeStep: Float = 1.0 / 60.0
    private let maxSubsteps = 3
    private let positionScale: Float = 1.6
    private let depthRange: ClosedRange<Float> = -0.25...0.25

    private var timeAccumulator: Float = 0
    private var forces: [SIMD3<Float>] = []

    func configure(graphData: GraphData?) {
        if let graphData, !graphData.nodes.isEmpty {
            buildNodes(from: graphData.nodes)
            buildEdges(from: graphData.edges, nodeCount: graphData.nodes.count)
        } else {
            buildNodes(count: defaultNodeCount)
            buildEdges(nodeCount: defaultNodeCount)
        }
        applyNodeVisuals()
    }

    private func buildNodes(count: Int) {
        nodes = (0..<count).map { _ in
            NetworkNode(
                position: randomPosition(in: initialRadius),
                velocity: .zero,
                radius: baseNodeRadius,
                color: UIColor.cyan
            )
        }
        forces = Array(repeating: .zero, count: count)
    }

    private func buildNodes(from input: [GraphNodeData]) {
        nodes = input.map { node in
            NetworkNode(
                position: node.position(scale: positionScale, depthRange: depthRange),
                velocity: .zero,
                radius: baseNodeRadius,
                color: UIColor.cyan
            )
        }
        forces = Array(repeating: .zero, count: nodes.count)
    }

    private func buildEdges(nodeCount: Int) {
        var generated: [NetworkEdge] = []

        for index in 1..<nodeCount {
            let target = Int.random(in: 0..<index)
            generated.append(NetworkEdge(a: index, b: target, restLength: springRestLength))
        }

        let extraEdges = nodeCount / 2
        for _ in 0..<extraEdges {
            let a = Int.random(in: 0..<nodeCount)
            var b = Int.random(in: 0..<nodeCount)
            while b == a {
                b = Int.random(in: 0..<nodeCount)
            }
            generated.append(NetworkEdge(a: a, b: b, restLength: springRestLength))
        }

        edges = generated
    }

    private func buildEdges(from input: [GraphEdgeData], nodeCount: Int) {
        edges = input.compactMap { edge in
            guard edge.source >= 0,
                  edge.target >= 0,
                  edge.source < nodeCount,
                  edge.target < nodeCount,
                  edge.source != edge.target else {
                return nil
            }
            return NetworkEdge(a: edge.source, b: edge.target, restLength: springRestLength)
        }
    }

    func step(deltaTime: Float) {
        let clampedDeltaTime = min(deltaTime, 1.0 / 20.0)
        guard clampedDeltaTime > 0 else { return }

        timeAccumulator += clampedDeltaTime
        var substepCount = 0

        while timeAccumulator >= fixedTimeStep && substepCount < maxSubsteps {
            simulateStep(deltaTime: fixedTimeStep)
            timeAccumulator -= fixedTimeStep
            substepCount += 1
        }
    }

    private func simulateStep(deltaTime: Float) {
        for index in 0..<forces.count {
            forces[index] = .zero
        }

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let offset = nodes[j].position - nodes[i].position
                let distance = max(simd_length(offset), 0.001)
                let direction = offset / distance
                let strength = repulsionStrength / (distance * distance)
                let force = direction * strength
                forces[i] -= force
                forces[j] += force
            }
        }

        for edge in edges {
            let offset = nodes[edge.b].position - nodes[edge.a].position
            let distance = max(simd_length(offset), 0.001)
            let direction = offset / distance
            let displacement = distance - edge.restLength
            let force = direction * (springStrength * displacement)
            forces[edge.a] += force
            forces[edge.b] -= force
        }

        for index in 0..<nodes.count {
            var node = nodes[index]
            node.velocity = (node.velocity + forces[index] * deltaTime) * damping

            let speed = simd_length(node.velocity)
            if speed > maxSpeed {
                node.velocity = (node.velocity / speed) * maxSpeed
            }

            node.position += node.velocity * deltaTime
            nodes[index] = node
        }
    }

    private func randomPosition(in radius: Float) -> SIMD3<Float> {
        var point = SIMD3<Float>(repeating: 0)

        repeat {
            point = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
        } while simd_length(point) > 1

        return point * radius
    }

    private func applyNodeVisuals() {
        let degreeCounts = degrees()
        let maxDegree = degreeCounts.max() ?? 1
        let minDegree = degreeCounts.min() ?? 0
        let degreeRange = max(maxDegree - minDegree, 1)

        for index in nodes.indices {
            let normalized = Float(degreeCounts[index] - minDegree) / Float(degreeRange)
            let radiusScale = lerp(from: 0.7, to: 1.45, t: normalized)
            nodes[index].radius = baseNodeRadius * radiusScale
            nodes[index].color = colorForNormalizedDegree(normalized)
        }
    }

    private func degrees() -> [Int] {
        var counts = Array(repeating: 0, count: nodes.count)
        for edge in edges {
            counts[edge.a] += 1
            counts[edge.b] += 1
        }
        return counts
    }

    private func lerp(from start: Float, to end: Float, t: Float) -> Float {
        start + (end - start) * max(0, min(1, t))
    }

    private func colorForNormalizedDegree(_ value: Float) -> UIColor {
        let clamped = max(0, min(1, value))
        let hue = 0.56 - (0.5 * Double(clamped))
        return UIColor(hue: CGFloat(hue), saturation: 0.7, brightness: 0.95, alpha: 1.0)
    }
}

private final class NetworkGraphRenderer {

    private let root = Entity()
    private var nodeEntities: [ModelEntity] = []
    private var edgeEntities: [ModelEntity] = []
    private var edges: [NetworkEdge] = []
    private let edgeRadius: Float = 0.004

    func build<Content: RealityViewContentProtocol>(
        content: inout Content,
        nodes: [NetworkNode],
        edges: [NetworkEdge]
    ) {
        self.edges = edges

        let nodeMesh = MeshResource.generateSphere(radius: 1.0)
        nodeEntities = nodes.map { node in
            let material = SimpleMaterial(color: node.color, roughness: 0.3, isMetallic: false)
            let entity = ModelEntity(mesh: nodeMesh, materials: [material])
            entity.position = node.position
            entity.scale = SIMD3<Float>(repeating: node.radius)
            return entity
        }

        let edgeMesh = MeshResource.generateCylinder(height: 1.0, radius: edgeRadius)
        let edgeMaterial = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.75), roughness: 0.5, isMetallic: false)
        edgeEntities = edges.map { _ in
            ModelEntity(mesh: edgeMesh, materials: [edgeMaterial])
        }

        for node in nodeEntities {
            root.addChild(node)
        }
        for edgeEntity in edgeEntities {
            root.addChild(edgeEntity)
        }

        root.scale = .init(x: 0.5, y: 0.5, z: 0.5)
        content.add(root)

        updateEdges(nodes: nodes)
    }

    func update(nodes: [NetworkNode]) {
        for index in nodes.indices {
            nodeEntities[index].position = nodes[index].position
        }
        updateEdges(nodes: nodes)
    }

    private func updateEdges(nodes: [NetworkNode]) {
        for (index, edge) in edges.enumerated() {
            let start = nodes[edge.a].position
            let end = nodes[edge.b].position
            let offset = end - start
            let distance = max(simd_length(offset), 0.001)
            let mid = (start + end) * 0.5

            let direction = offset / distance
            let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
            let scale = SIMD3<Float>(1, distance, 1)

            edgeEntities[index].transform = Transform(scale: scale, rotation: rotation, translation: mid)
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
