import Foundation

enum ClusterTextLibrary {
    static let defaultTexts: [String] = [
        "visionOS spatial computing user experience",
        "3D force-directed graph visualization",
        "knowledge clustering from short text",
        "semantic similarity and topic discovery",
        "interactive network exploration in XR",
        "graph nodes and edges layout",
        "human-computer interaction in space",
        "scene understanding and spatial anchors",
        "text embeddings and vector search",
        "cluster labeling and summarization",
        "real-time simulation stability",
        "data-driven storytelling with networks",
        "collaborative knowledge mapping",
        "visualizing relationships between ideas",
        "information architecture and navigation",
        "immersive analytics for complex data"
    ]
}

enum GraphDataLoader {
    private static let apiBaseURLString = "http://172.20.10.3:8000"
    private static let apiClusters = 5
    private static let apiTopEdges = 5

    static func loadDefaultGraphData() -> GraphData? {
        if let csvGraph = loadCSV(named: "cluster_points") {
            return csvGraph
        }
        return loadJSON(named: "graph_data")
    }

    static func loadCSV(named name: String, bundle: Bundle = .main) -> GraphData? {
        guard let url = bundle.url(forResource: name, withExtension: "csv"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        return graphData(fromCSVText: raw)
    }

    static func loadGraphDataFromAPI(texts: [String]) async -> GraphData? {
        guard let baseURL = URL(string: apiBaseURLString) else { return nil }

        let client = KnowledgeOrganizerClient(baseURL: baseURL)
        do {
            let csv = try await client.fetchClusterCSV(
                texts: texts,
                clusters: apiClusters,
                topEdges: apiTopEdges
            )
            return graphData(fromCSVText: csv)
        } catch {
            return nil
        }
    }

    static func loadJSON(named name: String, bundle: Bundle = .main) -> GraphData? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(GraphData.self, from: data)
    }

    private static func graphData(fromCSVText raw: String) -> GraphData? {
        let rows = parseCSV(raw)
        guard let header = rows.first else { return nil }

        let columnIndex = indexMap(from: header)
        guard let xIndex = columnIndex["x"],
              let yIndex = columnIndex["y"],
              let textIndex = columnIndex["text"],
              let clusterIndex = columnIndex["cluster"],
              let connectedIndex = columnIndex["connected_to"] else {
            return nil
        }

        var nodes: [GraphNodeData] = []
        var connections: [[Int]] = []

        for (rowIndex, row) in rows.dropFirst().enumerated() {
            guard row.count > max(xIndex, yIndex, textIndex, clusterIndex, connectedIndex) else { continue }

            let xValue = Float(row[xIndex]) ?? 0
            let yValue = Float(row[yIndex]) ?? 0
            let label = row[textIndex].isEmpty ? nil : row[textIndex]
            let clusterValue = Int(row[clusterIndex])
            let connectedRaw = row[connectedIndex]

            let node = GraphNodeData(
                id: rowIndex,
                x: xValue,
                y: yValue,
                z: nil,
                label: label,
                cluster: clusterValue
            )
            nodes.append(node)

            let connected = connectedRaw
                .split(separator: ";")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            connections.append(connected)
        }

        let edges = buildEdges(from: connections, nodeCount: nodes.count)
        return GraphData(nodes: nodes, edges: edges)
    }

    private static func indexMap(from header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (index, item) in header.enumerated() {
            map[item.lowercased()] = index
        }
        return map
    }

    private static func buildEdges(from connections: [[Int]], nodeCount: Int) -> [GraphEdgeData] {
        var edgeSet = Set<GraphEdgeData>()

        for (source, targets) in connections.enumerated() {
            for target in targets where target >= 0 && target < nodeCount && target != source {
                let edge = GraphEdgeData(
                    source: min(source, target),
                    target: max(source, target)
                )
                edgeSet.insert(edge)
            }
        }

        return edgeSet.sorted { lhs, rhs in
            if lhs.source == rhs.source {
                return lhs.target < rhs.target
            }
            return lhs.source < rhs.source
        }
    }

    private static func parseCSV(_ raw: String) -> [[String]] {
        raw
            .split(whereSeparator: \..isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { parseCSVLine($0) }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let nextChar = iterator.next() {
                        if nextChar == "\"" {
                            current.append("\"")
                        } else if nextChar == "," {
                            inQuotes = false
                            values.append(current)
                            current = ""
                        } else {
                            inQuotes = false
                            current.append(nextChar)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        values.append(current)
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
