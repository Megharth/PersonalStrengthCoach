import Foundation

struct AIInsightContext: Encodable {
    let readinessScore: Int
    let sleepHours: Double
    let hrv: Double
    let restingHeartRate: Double
    let weeklyVolume: Double
    let recommendation: String
}

private struct AIInsightResponse: Decodable {
    let text: String
}

private struct AIInsightRequest: Encodable {
    let question: String
    let context: AIInsightContext
}

enum AIInsightService {
    static func requestInsight(question: String, context: AIInsightContext) async throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AIProxyURL") as? String,
              let url = URL(string: value), !value.isEmpty else {
            throw URLError(.fileDoesNotExist)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AIInsightRequest(question: question, context: context))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AIInsightResponse.self, from: data).text
    }
}
