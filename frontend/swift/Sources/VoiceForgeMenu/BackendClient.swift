import Foundation

struct ProcessResponse: Codable {
    let text: String
    let rawText: String
    let intent: String
    let source: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case text
        case rawText = "raw_text"
        case intent
        case source
        case model
    }
}

private struct StopRequest: Codable {
    let selectedText: String?

    enum CodingKeys: String, CodingKey {
        case selectedText = "selected_text"
    }
}

private struct InjectionRequest: Codable {
    let text: String
    let rawText: String
    let intent: String
    let source: String
    let model: String
    let application: String

    enum CodingKeys: String, CodingKey {
        case text
        case rawText = "raw_text"
        case intent
        case source
        case model
        case application
    }
}

private struct APIError: Codable {
    let detail: String
}

final class BackendClient {
    private let baseURL = URL(string: "http://127.0.0.1:8765")!
    private let session = URLSession(
        configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 180
            return configuration
        }()
    )

    func health(completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        perform(request, responseType: EmptyResponse.self) { result in
            completion(result.map { _ in () })
        }
    }

    func startRecording(completion: @escaping (Result<Void, Error>) -> Void) {
        let request = postRequest(path: "v1/recording/start", body: Data("{}".utf8))
        perform(request, responseType: EmptyResponse.self) { result in
            completion(result.map { _ in () })
        }
    }

    func stopRecording(
        selectedText: String?,
        completion: @escaping (Result<ProcessResponse, Error>) -> Void
    ) {
        do {
            let body = try JSONEncoder().encode(StopRequest(selectedText: selectedText))
            let request = postRequest(path: "v1/recording/stop", body: body)
            perform(request, responseType: ProcessResponse.self, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func acknowledgeInjection(response: ProcessResponse, application: String) {
        let payload = InjectionRequest(
            text: response.text,
            rawText: response.rawText,
            intent: response.intent,
            source: response.source,
            model: response.model,
            application: application
        )
        guard let body = try? JSONEncoder().encode(payload) else { return }
        let request = postRequest(path: "v1/injection/completed", body: body)
        perform(request, responseType: EmptyResponse.self) { _ in }
    }

    private func postRequest(path: String, body: Data) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func perform<T: Decodable>(
        _ request: URLRequest,
        responseType: T.Type,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(ClientError.invalidResponse))
                return
            }
            let data = data ?? Data()
            guard (200..<300).contains(http.statusCode) else {
                let detail = (try? JSONDecoder().decode(APIError.self, from: data).detail)
                    ?? "HTTP \(http.statusCode)"
                completion(.failure(ClientError.server(detail)))
                return
            }
            if responseType == EmptyResponse.self {
                completion(.success(EmptyResponse() as! T))
                return
            }
            do {
                completion(.success(try JSONDecoder().decode(T.self, from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

private struct EmptyResponse: Codable {}

private enum ClientError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "后端返回格式无效。"
        case .server(let message):
            return message
        }
    }
}
