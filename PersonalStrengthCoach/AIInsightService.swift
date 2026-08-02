import Foundation

/// The only boundary where the app may ask an LLM for reasoning.
/// All score, volume, and PR values passed here have already been calculated locally.
struct AIInsightContext: Encodable {
    let readinessScore: Int
    let sleepHours: Double
    let hrv: Double
    let restingHeartRate: Double
    let weeklyVolume: Double
    let recommendation: String
}

enum AIInsightService {
    static let systemPrompt = """
    You are an elite strength coach. Use only the structured data supplied by the app.
    Never invent metrics or calculate values that are not supplied. Give concise, practical
    coaching in markdown, with at most three recommendations. Prioritize recovery and safe progression.
    """

    static func requestInsight(context: AIInsightContext, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let contextData = try JSONEncoder().encode(context)
        let json = String(decoding: contextData, as: UTF8.self)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-5-mini",
            "instructions": systemPrompt,
            "input": "Training context JSON:\n\(json)"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = payload?["output"] as? [[String: Any]] ?? []
        let content = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
