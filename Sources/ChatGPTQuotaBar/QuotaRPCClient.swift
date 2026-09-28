import Foundation

final class QuotaRPCClient {
    private let executableURL: URL?

    init(fileManager: FileManager = .default) {
        executableURL = Self.executableCandidates(fileManager: fileManager).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    func fetch(timeout: TimeInterval = 15) throws -> QuotaSnapshot {
        guard let executableURL else {
            throw QuotaError.executableMissing
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let stateQueue = DispatchQueue(label: "com.frankzhang.chatgpt-quota-bar.rpc")
        let completion = DispatchSemaphore(value: 0)
        var buffer = Data()
        var outcome: Result<QuotaSnapshot, Error>?
        var completed = false
        var readRequestSent = false

        func finish(_ result: Result<QuotaSnapshot, Error>) {
            stateQueue.async {
                guard !completed else { return }
                completed = true
                outcome = result
                completion.signal()
            }
        }

        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stateQueue.async {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    guard !line.isEmpty,
                          let message = try? JSONSerialization.jsonObject(with: Data(line)),
                          let envelope = message as? [String: Any],
                          let id = envelope["id"] as? Int else {
                        continue
                    }

                    if id == 1, !readRequestSent {
                        readRequestSent = true
                        do {
                            try send([
                                "id": 2,
                                "method": "account/rateLimits/read",
                                "params": NSNull(),
                            ])
                        } catch {
                            finish(.failure(error))
                        }
                    } else if id == 2 {
                        do {
                            finish(.success(try QuotaSnapshot.parseRPCResponse(envelope)))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                }
            }
        }

        process.terminationHandler = { terminatedProcess in
            finish(.failure(QuotaError.serverExited(terminatedProcess.terminationStatus)))
        }

        do {
            try process.run()
            try send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "chatgpt-quota-bar",
                        "version": "1.0.0",
                    ],
                    "capabilities": ["experimentalApi": true],
                ],
            ])
        } catch {
            if process.isRunning { process.terminate() }
            throw QuotaError.launch(error.localizedDescription)
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            finish(.failure(QuotaError.timeout))
            _ = completion.wait(timeout: .now() + 1)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? inputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForReading.close()

        let finalOutcome = stateQueue.sync { outcome }
        guard let finalOutcome else { throw QuotaError.timeout }
        return try finalOutcome.get()
    }

    private static func executableCandidates(fileManager: FileManager) -> [URL] {
        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let appNames = ["ChatGPT.app", "Codex.app"]
        let executablePaths = [
            // Current desktop builds bundle the CLI in this directory.
            "Contents/Resources/codex-cli/bin/codex",
            // Keep the nested app bundle as a fallback for packaging changes.
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            // Older desktop builds used this location.
            "Contents/Resources/codex",
        ]

        return [systemApplications, userApplications].flatMap { directory in
            appNames.flatMap { appName in
                executablePaths.map { executablePath in
                    directory
                        .appendingPathComponent(appName, isDirectory: true)
                        .appendingPathComponent(executablePath)
                }
            }
        }
    }
}
