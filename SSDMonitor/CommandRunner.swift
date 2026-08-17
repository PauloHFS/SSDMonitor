//
//  CommandRunner.swift
//  SSDMonitor
//
//  Abstração e adaptadores para execução de subprocessos CLI (diskutil, smartctl, lsof).
//

import Foundation

/// Resultado da execução de um subprocesso CLI.
public struct CommandExecutionResult: Sendable, Equatable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public let duration: TimeInterval

    public init(stdout: Data, stderr: Data, exitCode: Int32, duration: TimeInterval) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.duration = duration
    }
}

/// Seam para execução assíncrona de comandos CLI do sistema operacional.
public protocol CommandRunner: Sendable {
    func run(executable: String, arguments: [String], timeoutSeconds: Double) async -> CommandExecutionResult
}

/// Adaptador de produção: executa comandos do sistema usando a API Process() do Foundation.
public final class SystemCommandRunner: CommandRunner, @unchecked Sendable {
    public init() {}

    public func run(executable: String, arguments: [String], timeoutSeconds: Double = 2.0) async -> CommandExecutionResult {
        let startTime = Date()

        let result: (stdout: Data, stderr: Data, exitCode: Int32) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.currentDirectoryURL = URL(fileURLWithPath: "/")
                process.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                var outData = Data()
                var errData = Data()

                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global().async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                group.enter()
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (Data(), error.localizedDescription.data(using: .utf8) ?? Data(), -1))
                    return
                }

                let timeoutItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

                process.waitUntilExit()
                timeoutItem.cancel()
                group.wait()

                continuation.resume(returning: (outData, errData, process.terminationStatus))
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return CommandExecutionResult(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode, duration: duration)
    }
}

/// Adaptador de teste em memória: retorna respostas simuladas baseadas no executável/argumentos sem chamar o SO.
public final class InMemoryCommandRunner: CommandRunner, @unchecked Sendable {
    public typealias Handler = @Sendable (String, [String]) -> CommandExecutionResult
    
    private var responses: [String: CommandExecutionResult] = [:]
    private var handler: Handler?

    public init(responses: [String: CommandExecutionResult] = [:], handler: Handler? = nil) {
        self.responses = responses
        self.handler = handler
    }

    public func register(executable: String, result: CommandExecutionResult) {
        responses[executable] = result
    }

    public func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func run(executable: String, arguments: [String], timeoutSeconds: Double = 2.0) async -> CommandExecutionResult {
        if let handler = handler {
            return handler(executable, arguments)
        }
        if let response = responses[executable] {
            return response
        }
        return CommandExecutionResult(stdout: Data(), stderr: Data(), exitCode: -1, duration: 0.0)
    }
}
