//
//  ContentView.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI
import RealityKit
import simd

struct ContentView: View {

    @State private var simulation = NetworkGraphSimulation()

    var body: some View {
        RealityView { content in
            simulation.configureIfNeeded(content: &content)
        }
    }
}

private final class NetworkGraphSimulation {

    private struct Edge {
        let a: Int
        let b: Int
        let restLength: Float
    }

    private let root = Entity()
    private var nodes: [ModelEntity] = []
    private var velocities: [SIMD3<Float>] = []
    private var edges: [Edge] = []
    private var edgeEntities: [ModelEntity] = []
    private var updateSubscription: EventSubscription?
    private var isConfigured = false

    private let nodeCount = 16
    private let nodeRadius: Float = 0.05
    private let initialRadius: Float = 0.35
    private let springStrength: Float = 3.0
    private let springRestLength: Float = 0.25
    private let repulsionStrength: Float = 0.018
    private let damping: Float = 0.92
    private let maxSpeed: Float = 1.2
    private let edgeRadius: Float = 0.006

    func configureIfNeeded<Content: RealityViewContentProtocol>(content: inout Content) {
        guard !isConfigured else { return }
        isConfigured = true

        buildNodes()
        buildEdges()

        for node in nodes {
            root.addChild(node)
        }

        for edgeEntity in edgeEntities {
            root.addChild(edgeEntity)
        }

        root.scale = .init(x: 0.5, y: 0.5, z: 0.5)
        content.add(root)

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.step(deltaTime: Float(event.deltaTime))
        }
    }

    private func buildNodes() {
        let mesh = MeshResource.generateSphere(radius: nodeRadius)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .cyan)
        material.roughness = .init(floatLiteral: 0.25)
        material.metallic = .init(floatLiteral: 0.1)

        nodes = (0..<nodeCount).map { _ in
            let node = ModelEntity(mesh: mesh, materials: [material])
            node.position = randomPosition(in: initialRadius)
            return node
        }

        velocities = Array(repeating: .zero, count: nodeCount)
    }

    private func buildEdges() {
        var generated: [Edge] = []

        for index in 1..<nodeCount {
            let target = Int.random(in: 0..<index)
            generated.append(Edge(a: index, b: target, restLength: springRestLength))
        }

        let extraEdges = nodeCount / 2
        for _ in 0..<extraEdges {
            let a = Int.random(in: 0..<nodeCount)
            var b = Int.random(in: 0..<nodeCount)
            while b == a {
                b = Int.random(in: 0..<nodeCount)
            }
            generated.append(Edge(a: a, b: b, restLength: springRestLength))
        }

        edges = generated
        edgeEntities = generated.map { _ in
            let mesh = MeshResource.generateCylinder(height: 1.0, radius: edgeRadius)
            let material = SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)
            return ModelEntity(mesh: mesh, materials: [material])
        }

        updateEdges()
    }

    private func step(deltaTime: Float) {
        let clampedDeltaTime = min(deltaTime, 1.0 / 30.0)
        guard clampedDeltaTime > 0 else { return }

        var forces = Array(repeating: SIMD3<Float>(repeating: 0), count: nodes.count)

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
            velocities[index] = (velocities[index] + forces[index] * clampedDeltaTime) * damping

            let speed = simd_length(velocities[index])
            if speed > maxSpeed {
                velocities[index] = (velocities[index] / speed) * maxSpeed
            }

            nodes[index].position += velocities[index] * clampedDeltaTime
        }

        updateEdges()
    }

    private func updateEdges() {
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
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
