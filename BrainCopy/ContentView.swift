//
//  ContentView.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI
import Combine
import UIKit
import RealityKit
import simd

final class GraphUIState: ObservableObject {
    @Published var controls = GraphControls()
    @Published var selection: SelectedNode?
}

struct ContentView: View {

    @EnvironmentObject private var uiState: GraphUIState
    @Environment(\.openWindow) private var openWindow
    @State private var graphCoordinator = NetworkGraphCoordinator()

    var body: some View {
        RealityView { content in
            graphCoordinator.configureIfNeeded(content: &content)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    uiState.selection = graphCoordinator.handleTap(entity: value.entity)
                }
        )
        .onChange(of: uiState.controls) { _, newValue in
            graphCoordinator.updateControls(newValue)
        }
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.bottom),
            contentAlignment: .center
        ) {
            Button("Controls") {
                openWindow(id: "controlPanel")
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            graphCoordinator.updateControls(uiState.controls)
        }
    }
}

struct ControlPanelWindowView: View {
    @EnvironmentObject private var uiState: GraphUIState

    var body: some View {
        ControlPanel(controls: $uiState.controls, selection: uiState.selection)
    }
}

struct GraphControls: Equatable {
    var springStrength: Float = 2.8
    var repulsionStrength: Float = 0.018
    var damping: Float = 0.9
    var maxSpeed: Float = 1.1
    var graphScale: Float = 0.2
}

struct SelectedNode: Identifiable, Equatable {
    let id: Int
    let label: String
    let cluster: Int?
}

private struct ControlPanel: View {
    @Binding var controls: GraphControls
    let selection: SelectedNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                labeledSlider(title: "Spring", value: $controls.springStrength, range: 0.2...4.0)
                labeledSlider(title: "Repulsion", value: $controls.repulsionStrength, range: 0.001...0.05)
                labeledSlider(title: "Damping", value: $controls.damping, range: 0.6...0.99)
                labeledSlider(title: "Max Speed", value: $controls.maxSpeed, range: 0.3...2.5)
                labeledSlider(title: "Scale", value: $controls.graphScale, range: 0.2...1.0)
            }

            Divider()

            Text("Selection")
                .font(.headline)

            if let selection {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.label)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text("ID: \(selection.id)")
                        .font(.caption)
                    if let cluster = selection.cluster {
                        Text("Cluster: \(cluster)")
                            .font(.caption)
                    } else {
                        Text("Cluster: -")
                            .font(.caption)
                    }
                }
            } else {
                Text("No node selected")
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(16)
    }

    private func labeledSlider(title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title + ": " + String(format: "%.3f", value.wrappedValue))
                .font(.caption)
            Slider(
                value: value,
                in: range
            )
        }
    }
}

private final class NetworkGraphCoordinator {

    private let simulation = NetworkGraphSimulation()
    private let renderer = NetworkGraphRenderer()
    private var updateSubscription: EventSubscription?
    private var isConfigured = false
    private let graphData = GraphDataLoader.loadDefaultGraphData()
    private var selectedNodeIndex: Int?

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
        renderer.update(nodes: simulation.nodes, selectedIndex: selectedNodeIndex)
    }

    func updateControls(_ controls: GraphControls) {
        simulation.updateParameters(SimulationParameters(controls: controls))
        renderer.updateScale(controls.graphScale)
    }

    func handleTap(entity: Entity) -> SelectedNode? {
        guard let component = entity.components[NodeIdentifierComponent.self] else {
            return selectedNodeIndex.flatMap { selectionDetails(for: $0) }
        }

        if selectedNodeIndex == component.index {
            selectedNodeIndex = nil
        } else {
            selectedNodeIndex = component.index
        }

        renderer.updateSelection(selectedIndex: selectedNodeIndex, nodes: simulation.nodes)
        if let selectedNodeIndex {
            return selectionDetails(for: selectedNodeIndex)
        }
        return nil
    }

    private func selectionDetails(for index: Int) -> SelectedNode? {
        guard index >= 0, index < simulation.nodes.count else { return nil }
        let node = simulation.nodes[index]
        return SelectedNode(
            id: node.id,
            label: node.label ?? "Node \(node.id)",
            cluster: node.cluster
        )
    }
}

private struct NodeIdentifierComponent: Component {
    let index: Int
}

private struct NetworkNode {
    let id: Int
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var radius: Float
    var color: UIColor
    let label: String?
    let cluster: Int?
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
    private let springRestLength: Float = 0.23
    private let fixedTimeStep: Float = 1.0 / 60.0
    private let maxSubsteps = 3
    private let positionScale: Float = 1.6
    private let depthRange: ClosedRange<Float> = -0.25...0.25

    private var timeAccumulator: Float = 0
    private var forces: [SIMD3<Float>] = []
    private var parameters = SimulationParameters()

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
        nodes = (0..<count).map { index in
            NetworkNode(
                id: index,
                position: randomPosition(in: initialRadius),
                velocity: .zero,
                radius: baseNodeRadius,
                color: UIColor.cyan,
                label: nil,
                cluster: nil
            )
        }
        forces = Array(repeating: .zero, count: count)
    }

    private func buildNodes(from input: [GraphNodeData]) {
        nodes = input.map { node in
            NetworkNode(
                id: node.id,
                position: node.position(scale: positionScale, depthRange: depthRange),
                velocity: .zero,
                radius: baseNodeRadius,
                color: UIColor.cyan,
                label: node.label,
                cluster: node.cluster
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
                let strength = parameters.repulsionStrength / (distance * distance)
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
            let force = direction * (parameters.springStrength * displacement)
            forces[edge.a] += force
            forces[edge.b] -= force
        }

        for index in 0..<nodes.count {
            var node = nodes[index]
            node.velocity = (node.velocity + forces[index] * deltaTime) * parameters.damping

            let speed = simd_length(node.velocity)
            if speed > parameters.maxSpeed {
                node.velocity = (node.velocity / speed) * parameters.maxSpeed
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
            let radiusScale = lerp(from: 0.5, to: 1.9, t: normalized)
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

    func updateParameters(_ parameters: SimulationParameters) {
        self.parameters = parameters
    }
}

private struct SimulationParameters: Equatable {
    var springStrength: Float = 2.8
    var repulsionStrength: Float = 0.018
    var damping: Float = 0.9
    var maxSpeed: Float = 1.1

    init() {}

    init(controls: GraphControls) {
        springStrength = controls.springStrength
        repulsionStrength = controls.repulsionStrength
        damping = controls.damping
        maxSpeed = controls.maxSpeed
    }
}

private final class NetworkGraphRenderer {

    private let root = Entity()
    private var nodeEntities: [ModelEntity] = []
    private var edgeEntities: [ModelEntity] = []
    private var edges: [NetworkEdge] = []
    private let edgeRadius: Float = 0.004
    private var nodeBaseColors: [UIColor] = []
    private var labelEntity: ModelEntity?
    private var persistentLabelEntities: [Int: ModelEntity] = [:]
    private var persistentLabelIndices: [Int] = []
    private let labelOffset: Float = 0.06
    private var graphScale: Float = 0.5

    func build<Content: RealityViewContentProtocol>(
        content: inout Content,
        nodes: [NetworkNode],
        edges: [NetworkEdge]
    ) {
        self.edges = edges
        nodeBaseColors = nodes.map { $0.color }

        let nodeMesh = MeshResource.generateSphere(radius: 1.0)
        nodeEntities = nodes.enumerated().map { index, node in
            let material = SimpleMaterial(color: node.color, roughness: 0.3, isMetallic: false)
            let entity = ModelEntity(mesh: nodeMesh, materials: [material])
            entity.position = node.position
            entity.scale = SIMD3<Float>(repeating: node.radius)
            entity.components.set(NodeIdentifierComponent(index: index))
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: 1.0)]))
            entity.components.set(HoverEffectComponent())
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

        root.scale = .init(repeating: graphScale)
        content.add(root)

        updateEdges(nodes: nodes)
        buildPersistentLabels(nodes: nodes)
    }

    func update(nodes: [NetworkNode], selectedIndex: Int?) {
        for index in nodes.indices {
            nodeEntities[index].position = nodes[index].position
        }
        updateEdges(nodes: nodes)
        updatePersistentLabelsPosition(nodes: nodes)
        updateLabelPosition(nodes: nodes, selectedIndex: selectedIndex)
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

    func updateSelection(selectedIndex: Int?, nodes: [NetworkNode]) {
        for (index, entity) in nodeEntities.enumerated() {
            let color = nodeBaseColors[index]
            let isSelected = index == selectedIndex
            let materialColor = isSelected ? UIColor.systemYellow : color
            entity.model?.materials = [
                SimpleMaterial(color: materialColor, roughness: 0.2, isMetallic: false)
            ]
        }
        updateLabelText(nodes: nodes, selectedIndex: selectedIndex)
    }

    func updateScale(_ scale: Float) {
        graphScale = scale
        root.scale = .init(repeating: scale)
    }

    private func updateLabelText(nodes: [NetworkNode], selectedIndex: Int?) {
        guard let selectedIndex,
              selectedIndex >= 0,
              selectedIndex < nodes.count else {
            labelEntity?.removeFromParent()
            labelEntity = nil
            return
        }

        let node = nodes[selectedIndex]
        let labelText = node.label ?? "Node \(node.id)"

        let mesh = MeshResource.generateText(
            labelText,
            extrusionDepth: 0.002,
            font: UIFont.systemFont(ofSize: 0.12, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let material = SimpleMaterial(color: UIColor.white, roughness: 0.4, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.scale = SIMD3<Float>(repeating: 0.6)
        entity.components.set(BillboardComponent())
        labelEntity?.removeFromParent()
        labelEntity = entity
        root.addChild(entity)
    }

    private func buildPersistentLabels(nodes: [NetworkNode]) {
        persistentLabelEntities.values.forEach { $0.removeFromParent() }
        persistentLabelEntities.removeAll()
        persistentLabelIndices.removeAll()

        let degrees = degreeCounts(nodeCount: nodes.count)
        let labelMin = degreeQuantile(degrees, quantile: 0.9)

        for (index, node) in nodes.enumerated() {
            guard degrees[index] > 0 else { continue }
            guard degrees[index] >= labelMin else { continue }
            guard let label = node.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty else { continue }

            let mesh = MeshResource.generateText(
                label,
                extrusionDepth: 0.0015,
                font: UIFont.systemFont(ofSize: 0.08, weight: .medium),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )
            let material = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.85), roughness: 0.4, isMetallic: false)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.scale = SIMD3<Float>(repeating: 0.5)
            entity.components.set(BillboardComponent())
            root.addChild(entity)

            persistentLabelEntities[index] = entity
            persistentLabelIndices.append(index)
        }
    }

    private func updatePersistentLabelsPosition(nodes: [NetworkNode]) {
        for index in persistentLabelIndices {
            guard let labelEntity = persistentLabelEntities[index] else { continue }
            let node = nodes[index]
            let offset = labelOffset(for: labelEntity, nodeRadius: node.radius, extraOffset: labelOffset * 0.7)
            labelEntity.position = node.position + offset
        }
    }

    private func degreeCounts(nodeCount: Int) -> [Int] {
        var counts = Array(repeating: 0, count: nodeCount)
        for edge in edges {
            counts[edge.a] += 1
            counts[edge.b] += 1
        }
        return counts
    }

    private func degreeQuantile(_ degrees: [Int], quantile: Float) -> Int {
        guard !degrees.isEmpty else { return 0 }
        let sorted = degrees.sorted()
        let clampedQuantile = max(0, min(1, quantile))
        let position = Int(round(clampedQuantile * Float(sorted.count - 1)))
        return sorted[position]
    }

    private func updateLabelPosition(nodes: [NetworkNode], selectedIndex: Int?) {
        guard let selectedIndex,
              selectedIndex >= 0,
              selectedIndex < nodes.count,
              let labelEntity else {
            return
        }

        let node = nodes[selectedIndex]
        let offset = labelOffset(for: labelEntity, nodeRadius: node.radius, extraOffset: labelOffset)
        labelEntity.position = node.position + offset
    }

    private func labelOffset(for labelEntity: ModelEntity, nodeRadius: Float, extraOffset: Float) -> SIMD3<Float> {
        guard let bounds = labelEntity.model?.mesh.bounds else {
            return SIMD3<Float>(0, nodeRadius + extraOffset, 0)
        }

        let scaledCenter = bounds.center * labelEntity.scale
        let scaledHeight = bounds.extents.y * labelEntity.scale.y
        let offsetY = nodeRadius + extraOffset + (scaledHeight * 0.5)
        return SIMD3<Float>(-scaledCenter.x, offsetY - scaledCenter.y, -scaledCenter.z)
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environmentObject(GraphUIState())
}
