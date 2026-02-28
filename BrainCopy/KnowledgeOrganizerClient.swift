import Foundation

struct BrainCopyConfig: Codable {
    let apiBaseURL: String
    let clusters: Int?
    let topEdges: Int?

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case clusters
        case topEdges
    }
}

enum KnowledgeOrganizerError: Error {
    case invalidResponse
    case badStatusCode(Int)
    case invalidCSV
}

struct ClusterRequest: Codable {
    let texts: [String]
    let clusters: Int
    let topEdges: Int

    private enum CodingKeys: String, CodingKey {
        case texts
        case clusters
        case topEdges = "top_edges"
    }
}

final class KnowledgeOrganizerClient {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func fetchClusterCSV(texts: [String], clusters: Int?, topEdges: Int?) async throws -> String {
        let requestPayload = ClusterRequest(
            texts: texts,
            clusters: clusters ?? 5,
            topEdges: topEdges ?? 5
        )
        let url = baseURL.appendingPathComponent("cluster/points-csv")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KnowledgeOrganizerError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw KnowledgeOrganizerError.badStatusCode(httpResponse.statusCode)
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw KnowledgeOrganizerError.invalidCSV
        }
        return csv
    }
}
