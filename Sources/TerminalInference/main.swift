import AppleFM
import Foundation
import FoundationModels

struct Request: Decodable {
    let instructions: String
    let prompt: String
}

@available(macOS 26.0, *)
@Generable
struct TerminalAnswer {
    @Guide(description: "A brief explanation answering the user's question. Do not claim a command was executed.")
    var explanation: String
    @Guide(description: "The corrected NEXT command, never the original failed command. Empty when clarification is needed.")
    var next_command: String
}

@main
struct TerminalInference {
    static func emit(_ value: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }

    static func main() async {
        let client = AppleFMClient()
        if CommandLine.arguments.dropFirst().first == "--availability" {
            emit(["availability": client.modelAvailability.rawValue, "backend": "AppleFM Swift"])
            return
        }
        do {
            let input = FileHandle.standardInput.readData(ofLength: 32_001)
            guard input.count <= 32_000 else { emit(["error": "Request exceeds the input limit."]); return }
            let request = try JSONDecoder().decode(Request.self, from: input)
            guard request.prompt.count <= 16_000, request.instructions.count <= 5_000 else {
                emit(["error": "Request exceeds the context limit."]); return
            }
            guard #available(macOS 26.0, *) else { emit(["error": "macOS 26 or later is required."]); return }
            let answer = try await client.generate(
                instructions: request.instructions,
                prompt: request.prompt,
                generating: TerminalAnswer.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 400)
            )
            emit(["explanation": answer.explanation, "next_command": answer.next_command])
        } catch AppleFMError.unavailable(let reason) {
            emit(["error": "Apple Intelligence is unavailable: \(reason.rawValue). Run apple-fm-terminal doctor."])
        } catch is CancellationError {
            emit(["error": "Request cancelled."])
        } catch {
            // Never print an underlying model error: it may contain request text.
            emit(["error": "Local generation failed. No command was accepted."])
        }
    }
}
