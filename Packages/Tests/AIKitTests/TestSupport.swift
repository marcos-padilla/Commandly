import Foundation
@testable import AIKit

actor ScriptedAIHTTPTransport: AIHTTPTransport {
    private var responses: [AIHTTPResponse]
    private var requests: [AIHTTPRequest] = []

    init(responses: [AIHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw AIProviderError.invalidProviderResponse }
        return responses.removeFirst()
    }

    func recordedRequests() -> [AIHTTPRequest] {
        requests
    }
}

func jsonResponse(_ json: String, statusCode: Int = 200) -> AIHTTPResponse {
    AIHTTPResponse(
        statusCode: statusCode,
        headers: ["Content-Type": "application/json"],
        body: Data(json.utf8)
    )
}

func testBaseURL(_ path: String = "/v1") -> URL {
    URL(string: "https://provider.test\(path)") ?? URL(fileURLWithPath: "/")
}

func testTool() -> AIToolDefinition {
    AIToolDefinition(
        name: "finder_list",
        description: "List the immediate children of a folder.",
        inputSchema: .closedObject(
            properties: [
                "path": .string(allowedValues: nil, description: "Folder path")
            ],
            required: ["path"]
        ),
        effect: .readOnly,
        confirmation: .never
    )
}

func testConfiguration(_ providerID: AIProviderID) -> AIProviderConfiguration {
    AIProviderConfiguration(providerID: providerID, credential: AICredential("test-secret"))
}

func decodedBody(_ request: AIHTTPRequest) throws -> AIJSONValue {
    guard let body = request.body else { throw AIProviderError.invalidRequest }
    return try AIJSONValue(data: body)
}
