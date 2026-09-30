import Foundation
import FoundationModels

enum AppleIntelligenceError: LocalizedError {
    case unavailable(SystemLanguageModel.Availability)

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return "Apple Intelligence isn't available (\(availability)). Check System Settings → Apple Intelligence & Siri."
        }
    }
}

/// Generates structured content using Apple's on-device model. Nothing leaves the Mac.
struct AppleIntelligenceClient {
    static let `default` = AppleIntelligenceClient()

    func respond(to prompt: String, schema: GenerationSchema, temperature: Double? = nil) async throws
        -> GeneratedContent
    {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw AppleIntelligenceError.unavailable(model.availability)
        }

        let session = LanguageModelSession()
        let response = try await session.respond(
            schema: schema,
            options: GenerationOptions(temperature: temperature)
        ) {
            prompt
        }
        return response.content
    }
}
