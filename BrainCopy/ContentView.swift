//
//  ContentView.swift
//  BrainCopy
//
//  Created by 酒井雄太 on 2026/02/28.
//

import SwiftUI
import Combine
import Foundation
import UniformTypeIdentifiers
import UIKit
import RealityKit
import simd

final class GraphUIState: ObservableObject {
    @Published var controls = GraphControls()
    @Published var selection: SelectedNode?
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TextFileParseResult {
    let texts: [String]
    let warning: String?
}

private enum TextFileParser {
    private static let maxTexts = 2000
    private static let delimiters = ["|||", "||", "|", ";;", ";", ",", "\t"]

    static func parse(_ raw: String) -> TextFileParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TextFileParseResult(texts: [], warning: nil)
        }

        let lineTexts = splitLines(trimmed)
        if lineTexts.count > 1 {
            return applyLimit(to: lineTexts)
        }

        for delimiter in delimiters {
            let parts = splitByDelimiter(trimmed, delimiter: delimiter)
            if parts.count > 1 {
                return applyLimit(to: parts)
            }
        }

        return TextFileParseResult(texts: [trimmed], warning: nil)
    }

    private static func splitLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: \..isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitByDelimiter(_ text: String, delimiter: String) -> [String] {
        text
            .components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func applyLimit(to texts: [String]) -> TextFileParseResult {
        guard texts.count > maxTexts else {
            return TextFileParseResult(texts: texts, warning: nil)
        }

        let limited = Array(texts.prefix(maxTexts))
        let warning = "テキスト数が多いため、先頭\(maxTexts)件のみで処理します。"
        return TextFileParseResult(texts: limited, warning: warning)
    }
}

struct ContentView: View {

    @EnvironmentObject private var uiState: GraphUIState
    @State private var graphCoordinator = NetworkGraphCoordinator()
    @State private var dataLoadTask: Task<Void, Never>?
    @State private var hasTriggeredInitialLoad = false
    @State private var isLoadingAPI = false
    @State private var isImportingTextFile = false
    @State private var importAlert: ImportAlert?
    @State private var hasPresentedFileImporter = false

    var body: some View {
        RealityView { content in
            graphCoordinator.configureIfNeeded(content: &content)
        }
        .overlay(alignment: .center) {
            if isLoadingAPI {
                ProgressView()
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .targetedToAnyEntity()
                .onChanged { value in
                    graphCoordinator.handleDragChanged(value)
                }
                .onEnded { value in
                    graphCoordinator.handleDragEnded(value)
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    graphCoordinator.handleMagnifyChanged(value.magnification)
                }
                .onEnded { value in
                    graphCoordinator.handleMagnifyEnded(value.magnification)
                }
        )
        .simultaneousGesture(
            RotateGesture()
                .onChanged { value in
                    graphCoordinator.handleRotateChanged(value.rotation)
                }
                .onEnded { value in
                    graphCoordinator.handleRotateEnded(value.rotation)
                }
        )
        .simultaneousGesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    uiState.selection = graphCoordinator.handleTap(entity: value.entity)
                }
        )
        .onChange(of: uiState.controls) { _, newValue in
            graphCoordinator.updateControls(newValue)
        }
        .fileImporter(
            isPresented: $isImportingTextFile,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false,
            onCompletion: handleTextFileImport
        )
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
//        .ornament(
//            visibility: .visible,
//            attachmentAnchor: .scene(.bottom),
//            contentAlignment: .center
//        ) {
//            Button("Controls") {
//                openWindow(id: "controlPanel")
//            }
//            .buttonStyle(.borderedProminent)
//        }
        .onAppear {
            graphCoordinator.updateControls(uiState.controls)
            if !hasTriggeredInitialLoad {
                hasTriggeredInitialLoad = true
            }
            if !hasPresentedFileImporter {
                hasPresentedFileImporter = true
                isImportingTextFile = true
            }
        }
    }

    private func reloadGraphData() {
        loadGraphData(texts: ClusterTextLibrary.defaultTexts)
    }

    private func loadGraphData(texts: [String]) {
        dataLoadTask?.cancel()
        isLoadingAPI = true

        dataLoadTask = Task {
            let graphData = await GraphDataLoader.loadGraphDataFromAPI(texts: texts)
            await MainActor.run {
                if let graphData {
                    graphCoordinator.queueGraphData(graphData) {
                        isLoadingAPI = false
                    }
                } else {
                    isLoadingAPI = false
                    importAlert = ImportAlert(
                        title: "読み込みエラー",
                        message: "APIからグラフデータを取得できませんでした。"
                    )
                }
            }
        }
    }

    private func handleTextFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importAlert = ImportAlert(
                    title: "ファイル選択エラー",
                    message: "ファイルが選択されませんでした。"
                )
                return
            }
            Task {
                await importTextFile(url)
            }
        case .failure(let error):
            importAlert = ImportAlert(
                title: "ファイル選択エラー",
                message: error.localizedDescription
            )
        }
    }

    private func importTextFile(_ url: URL) async {
        let loadResult = await readTextFile(url)
        switch loadResult {
        case .success(let rawText):
            let parseResult = TextFileParser.parse(rawText)
            guard !parseResult.texts.isEmpty else {
                importAlert = ImportAlert(
                    title: "読み込みエラー",
                    message: "テキストが見つかりませんでした。改行区切りか区切り記号で入力してください。"
                )
                return
            }
            if let warning = parseResult.warning {
                importAlert = ImportAlert(
                    title: "読み込みメモ",
                    message: warning
                )
            }
            loadGraphData(texts: parseResult.texts)
        case .failure:
            importAlert = ImportAlert(
                title: "ファイル読み込みエラー",
                message: "UTF-8のテキストファイルを選択してください。"
            )
        }
    }

    private func readTextFile(_ url: URL) async -> Result<String, Error> {
        await Task.detached {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                return .success(text)
            } catch {
                return .failure(error)
            }
        }.value
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


private final class NetworkGraphCoordinator {

    private let simulation = NetworkGraphSimulation()
    private let renderer = NetworkGraphRenderer()
    private var updateSubscription: EventSubscription?
    private var isConfigured = false
    private var isPrewarming = false
    private var graphData = GraphDataLoader.loadDefaultGraphData()
    private var selectedNodeIndex: Int?
    private var draggedNodeIndex: Int?
    private let prewarmMaxSteps = 1200
    private let prewarmTargetSpeed: Float = 0.005
    private var baseScale: Float = 0.2
    private var gestureScale: Float = 1.0
    private var baseRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var gestureRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var pendingGraphData: GraphData?
    private var onRenderReady: (() -> Void)?

    func configureIfNeeded<Content: RealityViewContentProtocol>(content: inout Content) {
        guard !isConfigured else { return }
        isConfigured = true

        simulation.configure(graphData: graphData)
        renderer.build(content: &content, nodes: simulation.nodes, edges: simulation.edges)
        renderer.setVisible(false)

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.step(deltaTime: Float(event.deltaTime))
        }

        startPrewarm()
    }

    private func startPrewarm(force: Bool = false) {
        if isPrewarming, !force { return }
        isPrewarming = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.simulation.prewarm(maxSteps: self.prewarmMaxSteps, targetMaxSpeed: self.prewarmTargetSpeed)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.renderer.update(nodes: self.simulation.nodes, selectedIndex: self.selectedNodeIndex)
                self.renderer.setVisible(true)
                self.isPrewarming = false
                let completion = self.onRenderReady
                self.onRenderReady = nil
                completion?()
                if let pending = self.pendingGraphData {
                    self.pendingGraphData = nil
                    self.applyGraphData(pending)
                }
            }
        }
    }

    @MainActor
    private func applyGraphData(_ graphData: GraphData) {
        self.graphData = graphData
        selectedNodeIndex = nil
        renderer.setVisible(false)
        simulation.reconfigure(graphData: graphData)
        renderer.rebuild(nodes: simulation.nodes, edges: simulation.edges)
        startPrewarm(force: true)
    }

    @MainActor
    func queueGraphData(_ graphData: GraphData, onRenderReady: (() -> Void)? = nil) {
        self.onRenderReady = onRenderReady
        if isPrewarming {
            pendingGraphData = graphData
        } else {
            applyGraphData(graphData)
        }
    }

    private func step(deltaTime: Float) {
        guard !isPrewarming else { return }
        simulation.step(deltaTime: deltaTime)
        renderer.update(nodes: simulation.nodes, selectedIndex: selectedNodeIndex)
    }

    func updateControls(_ controls: GraphControls) {
        simulation.updateParameters(SimulationParameters(controls: controls))
        baseScale = controls.graphScale
        applyRootTransform()
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

    func handleDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !isPrewarming else { return }
        guard let component = value.entity.components[NodeIdentifierComponent.self] else { return }
        guard let parent = value.entity.parent else { return }

        let position = value.convert(value.location3D, from: .global, to: parent)
        draggedNodeIndex = component.index
        simulation.updateDraggedNode(index: component.index, position: position)
        renderer.update(nodes: simulation.nodes, selectedIndex: selectedNodeIndex)
    }

    func handleDragEnded(_ value: EntityTargetValue<DragGesture.Value>) {
        guard !isPrewarming else { return }
        guard let component = value.entity.components[NodeIdentifierComponent.self] else { return }

        if draggedNodeIndex == component.index {
            draggedNodeIndex = nil
            simulation.endDrag()
        }
    }

    func handleMagnifyChanged(_ magnification: CGFloat) {
        gestureScale = clampScale(Float(magnification))
        applyRootTransform()
    }

    func handleMagnifyEnded(_ magnification: CGFloat) {
        baseScale = clampScale(baseScale * Float(magnification))
        gestureScale = 1.0
        applyRootTransform()
    }

    func handleRotateChanged(_ rotation: Angle) {
        gestureRotation = simd_quatf(angle: Float(rotation.radians), axis: SIMD3<Float>(0, 1, 0))
        applyRootTransform()
    }

    func handleRotateEnded(_ rotation: Angle) {
        baseRotation = baseRotation * simd_quatf(angle: Float(rotation.radians), axis: SIMD3<Float>(0, 1, 0))
        gestureRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        applyRootTransform()
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

    private func applyRootTransform() {
        let scale = clampScale(baseScale * gestureScale)
        let rotation = baseRotation * gestureRotation
        renderer.updateRootTransform(scale: scale, rotation: rotation)
    }

    private func clampScale(_ value: Float) -> Float {
        max(0.05, min(3.0, value))
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
    private let fixedTimeStep: Float = 1.0 / 90.0
    private let maxSubsteps = 6
    private let positionScale: Float = 1.6
    private let depthRange: ClosedRange<Float> = -0.25...0.25

    private var timeAccumulator: Float = 0
    private var forces: [SIMD3<Float>] = []
    private var parameters = SimulationParameters()
    private var draggedNodeIndex: Int?
    private var draggedNodePosition: SIMD3<Float> = .zero

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

    func reconfigure(graphData: GraphData?) {
        timeAccumulator = 0
        draggedNodeIndex = nil
        draggedNodePosition = .zero
        configure(graphData: graphData)
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

    func prewarm(maxSteps: Int, targetMaxSpeed: Float) {
        guard maxSteps > 0 else { return }

        for _ in 0..<maxSteps {
            simulateStep(deltaTime: fixedTimeStep)
            if maxNodeSpeed() <= targetMaxSpeed {
                break
            }
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
        if let draggedNodeIndex, draggedNodeIndex >= 0, draggedNodeIndex < nodes.count {
            nodes[draggedNodeIndex].position = draggedNodePosition
            nodes[draggedNodeIndex].velocity = .zero
        }

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
            if index == draggedNodeIndex {
                continue
            }
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

    private func maxNodeSpeed() -> Float {
        var maxSpeed: Float = 0

        for node in nodes {
            maxSpeed = max(maxSpeed, simd_length(node.velocity))
        }

        return maxSpeed
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

    func updateDraggedNode(index: Int, position: SIMD3<Float>) {
        draggedNodeIndex = index
        draggedNodePosition = position
        if index >= 0, index < nodes.count {
            nodes[index].position = position
            nodes[index].velocity = .zero
        }
    }

    func endDrag() {
        draggedNodeIndex = nil
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
    private let labelBackgroundPadding: Float = 0.02
    private let labelBackgroundCornerRadius: Float = 0.02
    private let labelBackgroundDepthOffset: Float = 0.002
    private var graphScale: Float = 0.5
    private var graphRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    func build<Content: RealityViewContentProtocol>(
        content: inout Content,
        nodes: [NetworkNode],
        edges: [NetworkEdge]
    ) {
        resetEntities()
        configureEntities(nodes: nodes, edges: edges)
        applyRootTransform()
        content.add(root)
        updateEdges(nodes: nodes)
        buildPersistentLabels(nodes: nodes)
    }

    func rebuild(nodes: [NetworkNode], edges: [NetworkEdge]) {
        resetEntities()
        configureEntities(nodes: nodes, edges: edges)
        applyRootTransform()
        updateEdges(nodes: nodes)
        buildPersistentLabels(nodes: nodes)
    }

    private func resetEntities() {
        labelEntity?.removeFromParent()
        labelEntity = nil
        persistentLabelEntities.values.forEach { $0.removeFromParent() }
        persistentLabelEntities.removeAll()
        persistentLabelIndices.removeAll()
        nodeEntities.removeAll()
        edgeEntities.removeAll()
        edges = []
        nodeBaseColors = []
        while let child = root.children.first {
            child.removeFromParent()
        }
    }

    private func configureEntities(nodes: [NetworkNode], edges: [NetworkEdge]) {
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

    func updateRootTransform(scale: Float, rotation: simd_quatf) {
        graphScale = scale
        graphRotation = rotation
        applyRootTransform()
    }

    private func applyRootTransform() {
        root.transform.scale = SIMD3<Float>(repeating: graphScale)
        root.transform.rotation = graphRotation
    }

    func setVisible(_ isVisible: Bool) {
        root.isEnabled = isVisible
    }

    private func updateLabelText(nodes: [NetworkNode], selectedIndex: Int?) {
        guard let selectedIndex,
              selectedIndex >= 0,
              selectedIndex < nodes.count else {
            labelEntity?.removeFromParent()
            labelEntity = nil
            return
        }

        if persistentLabelEntities[selectedIndex] != nil {
            labelEntity?.removeFromParent()
            labelEntity = nil
            return
        }

        let node = nodes[selectedIndex]
        let labelText = node.label ?? "Node \(node.id)"

        let entity = makeLabelEntity(
            text: labelText,
            textColor: UIColor.white,
            textAlpha: 1.0
        )
        entity.scale = SIMD3<Float>(repeating: 0.5)
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

            let entity = makeLabelEntity(
                text: label,
                textColor: UIColor.white,
                textAlpha: 0.85
            )
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
        let paddedHeight = bounds.extents.y + (labelBackgroundPadding * 2)
        let scaledHeight = paddedHeight * labelEntity.scale.y
        let offsetY = nodeRadius + extraOffset + (scaledHeight * 0.5)
        return SIMD3<Float>(-scaledCenter.x, offsetY - scaledCenter.y, -scaledCenter.z)
    }

    private func makeLabelEntity(text: String, textColor: UIColor, textAlpha: CGFloat) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0015,
            font: UIFont.systemFont(ofSize: 0.08, weight: .medium),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let material = SimpleMaterial(color: textColor.withAlphaComponent(textAlpha), roughness: 0.4, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        addBackground(to: entity, textMesh: mesh)
        return entity
    }

    private func addBackground(to labelEntity: ModelEntity, textMesh: MeshResource) {
        let bounds = textMesh.bounds
        let width = bounds.extents.x + (labelBackgroundPadding * 2)
        let height = bounds.extents.y + (labelBackgroundPadding * 2)
        let cornerRadius = min(labelBackgroundCornerRadius, min(width, height) * 0.5)
        let backgroundMesh = MeshResource.generatePlane(
            width: width,
            height: height,
            cornerRadius: cornerRadius
        )
        let backgroundColor = UIColor.black.withAlphaComponent(0.7)
        let backgroundMaterial = SimpleMaterial(color: backgroundColor, roughness: 0.7, isMetallic: false)
        let backgroundEntity = ModelEntity(mesh: backgroundMesh, materials: [backgroundMaterial])
        backgroundEntity.position = SIMD3<Float>(
            bounds.center.x,
            bounds.center.y,
            bounds.center.z - bounds.extents.z - labelBackgroundDepthOffset
        )
        labelEntity.addChild(backgroundEntity)
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environmentObject(GraphUIState())
}
