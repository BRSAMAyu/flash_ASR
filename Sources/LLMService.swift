import Foundation

enum LLMProviderType: String {
    case primary // MiMo or the main selected one
    case secondary // GLM in dual mode
}

final class LLMService {
    private var activeClients: [LLMProviderType: MiMoClient] = [:]
    private let queue = DispatchQueue(label: "llm.service.queue")

    func startRequest(
        mode: String, // "mimo", "glm", "dual"
        settings: SettingsManager,
        systemPrompt: String,
        userContent: String,
        onDelta: @escaping (String, LLMProviderType) -> Void,
        onComplete: @escaping (String, LLMProviderType) -> Void,
        onError: @escaping (String, LLMProviderType) -> Void
    ) {
        cancelAll()

        queue.async {
            // Determine configs based on mode
            var configs: [(type: LLMProviderType, apiKey: String, endpoint: String, model: String, temp: Double, maxTokens: Int, disableThinking: Bool, name: String)] = []

            // Primary config
            if mode == "glm" {
                configs.append((
                    .primary,
                    settings.glmAPIKey,
                    settings.glmBaseURL,
                    settings.glmModel,
                    0.7,
                    4096,
                    false,
                    "GLM"
                ))
            } else {
                // "mimo" or "dual" - Primary is MiMo
                configs.append((
                    .primary,
                    settings.mimoAPIKey,
                    settings.mimoBaseURL,
                    settings.mimoModel,
                    0.3,
                    2048,
                    true,
                    "MiMo"
                ))
            }

            // Secondary config (only for dual mode)
            if mode == "dual" {
                configs.append((
                    .secondary,
                    settings.glmAPIKey,
                    settings.glmBaseURL,
                    settings.glmModel,
                    0.7,
                    4096,
                    false,
                    "GLM"
                ))
            }

            // Launch clients
            for config in configs {
                guard let ep = URL(string: config.endpoint) else {
                    onError("Invalid URL for \(config.name)", config.type)
                    continue
                }

                let client = MiMoClient(
                    apiKey: config.apiKey,
                    endpoint: ep,
                    model: config.model,
                    temperature: config.temp,
                    maxTokens: config.maxTokens,
                    disableThinking: config.disableThinking
                )

                self.activeClients[config.type] = client

                var accumulated = ""
                
                client.onDelta = { delta in
                    accumulated += delta
                    onDelta(delta, config.type)
                }

                client.onError = { msg in
                    Console.line("LLM Error (\(config.name)): \(msg)")
                    onError(msg, config.type)
                }

                client.onDone = { [weak self] in
                    self?.queue.async {
                        self?.activeClients[config.type] = nil
                    }
                    onComplete(accumulated, config.type)
                }

                Console.line("Starting \(config.name) request (Mode: \(mode))...")
                client.start(systemPrompt: systemPrompt, userContent: userContent)
            }
        }
    }

    func cancelAll() {
        queue.async {
            for client in self.activeClients.values {
                client.cancel()
            }
            self.activeClients.removeAll()
        }
    }
}
