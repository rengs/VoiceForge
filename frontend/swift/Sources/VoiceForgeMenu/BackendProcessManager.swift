import Foundation

final class BackendProcessManager {
    private var ownedProcess: Process?
    private var ollamaProcess: Process?

    var projectRoot: URL? {
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoiceForge")
            .appendingPathComponent("project-root")
        guard let value = try? String(contentsOf: config, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    func startIfNeeded() {
        guard let root = projectRoot else { return }
        startOllamaIfPresent(root: root)
        let python = root.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return }

        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "backend.main", "serve"]
        process.currentDirectoryURL = root
        let logURL = root.appendingPathComponent("data/backend.log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
            ownedProcess = process
        } catch {
            ownedProcess = nil
        }
    }

    func stopOwnedProcess() {
        if let process = ownedProcess, process.isRunning {
            process.terminate()
        }
        ownedProcess = nil
        if let ollamaProcess, ollamaProcess.isRunning {
            ollamaProcess.terminate()
        }
        ollamaProcess = nil
    }

    private func startOllamaIfPresent(root: URL) {
        let binary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Applications/Ollama.app/Contents/Resources/ollama"
            )
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            return
        }
        let logURL = root.appendingPathComponent("data/ollama.log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve"]
        if let log = try? FileHandle(forWritingTo: logURL) {
            try? log.seekToEnd()
            process.standardOutput = log
            process.standardError = log
        }
        do {
            try process.run()
            ollamaProcess = process
        } catch {
            ollamaProcess = nil
        }
    }

    func runDoctor(completion: @escaping (String) -> Void) {
        guard let root = projectRoot else {
            completion("未找到项目配置，请重新运行 install.sh。")
            return
        }
        let process = Process()
        process.executableURL = root.appendingPathComponent(".venv/bin/python")
        process.arguments = ["-m", "backend.main", "doctor"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            completion(String(data: data, encoding: .utf8) ?? "诊断没有输出。")
        }
        do {
            try process.run()
        } catch {
            completion(error.localizedDescription)
        }
    }
}
