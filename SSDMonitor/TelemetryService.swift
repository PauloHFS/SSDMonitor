//
//  TelemetryService.swift
//  SSDMonitor
//
//  Executor assíncrono de subprocessos (smartctl, lsof, diskutil unmount) com logging.
//

import Foundation
import AppKit

// MARK: - Logger Helper

public nonisolated func logTelemetry(_ message: String, isError: Bool = false) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timeStr = formatter.string(from: Date())
    let icon = isError ? "❌" : "ℹ️"
    print("[\(timeStr)] [TelemetryService] \(icon) \(message)")
    fflush(stdout)
}

// MARK: - Modelos de Dados

public struct ActiveProcess: Identifiable, Hashable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let openFiles: [String]

    public nonisolated init(pid: pid_t, name: String, openFiles: [String]) {
        self.pid = pid
        self.name = name
        self.openFiles = openFiles
    }
}

public struct StorageInfo: Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public nonisolated var usedBytes: Int64 { totalBytes - freeBytes }
    public nonisolated var usedRatio: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0.0
    }
    
    public nonisolated init(totalBytes: Int64, freeBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }
}

public struct SMARTData: Sendable {
    public let temperature: Int?
    public let smartPassed: Bool?
    public let modelName: String?
    public let rawError: String?

    public nonisolated init(temperature: Int?, smartPassed: Bool?, modelName: String?, rawError: String? = nil) {
        self.temperature = temperature
        self.smartPassed = smartPassed
        self.modelName = modelName
        self.rawError = rawError
    }
}

// MARK: - Telemetry Service Actor

public actor TelemetryService {
    public static let shared = TelemetryService()
    
    private let commandRunner: CommandRunner
    
    public init(commandRunner: CommandRunner = SystemCommandRunner()) {
        self.commandRunner = commandRunner
    }
    
    /// Executor genérico de subprocessos assíncrono delegando para a interface CommandRunner
    private func runSubprocess(executable: String, arguments: [String], timeoutSeconds: Double = 2.0) async -> CommandExecutionResult {
        return await commandRunner.run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds)
    }
    /// Localiza o binário do smartctl nos caminhos padrão do macOS / Homebrew
    public func findSmartctlExecutable() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/smartctl",
            "/usr/local/bin/smartctl",
            "/opt/homebrew/sbin/smartctl",
            "/usr/bin/smartctl"
        ]
        let fm = FileManager.default
        let path = possiblePaths.first { fm.isExecutableFile(atPath: $0) }
        if let found = path {
            logTelemetry("smartctl encontrado em: \(found)")
        } else {
            logTelemetry("smartctl NÃO encontrado nos caminhos padrão!", isError: true)
        }
        return path
    }
    
    /// Detecta dinamicamente o identificador físico (ex: /dev/disk8 ou /dev/disk9) via diskutil info
    public func detectBSDNode(forVolumePath volumePath: String) async -> String {
        let defaultNode = "/dev/disk8"
        guard FileManager.default.fileExists(atPath: volumePath) else {
            logTelemetry("Volume \(volumePath) não existe no sistema de arquivos.", isError: true)
            return defaultNode
        }
        
        logTelemetry("Executando diskutil info -plist \(volumePath)...")
        let result = await runSubprocess(executable: "/usr/sbin/diskutil", arguments: ["info", "-plist", volumePath], timeoutSeconds: 1.5)
        
        guard !result.stdout.isEmpty else {
            logTelemetry("diskutil não retornou dados. Usando padrão: \(defaultNode)", isError: true)
            return defaultNode
        }
        
        if let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any] {
            var node: String? = nil
            if let parentWhole = plist["ParentWholeDisk"] as? String {
                node = "/dev/\(parentWhole)"
            } else if let devNode = plist["DeviceNode"] as? String {
                node = devNode
            } else if let devId = plist["DeviceIdentifier"] as? String {
                node = "/dev/\(devId)"
            }
            
            if let detected = node {
                logTelemetry("Nó BSD detectado para \(volumePath): \(detected) (tempo: \(String(format: "%.3fs", result.duration)))")
                return detected
            }
        }
        
        logTelemetry("Falha ao parsear plist do diskutil. Usando padrão: \(defaultNode)", isError: true)
        return defaultNode
    }
    
    /// Executa o smartctl em background e parseia a temperatura e status SMART
    public func fetchSMARTData(deviceNode: String) async -> SMARTData {
        guard let smartctlPath = findSmartctlExecutable() else {
            let err = "smartctl não instalado em /opt/homebrew/bin ou /usr/local/bin"
            logTelemetry(err, isError: true)
            return SMARTData(temperature: nil, smartPassed: nil, modelName: nil, rawError: err)
        }
        
        logTelemetry("Lendo SMART em \(deviceNode) via \(smartctlPath)...")
        let result = await runSubprocess(executable: smartctlPath, arguments: ["--json=c", "-a", deviceNode], timeoutSeconds: 2.0)
        
        if result.stdout.isEmpty {
            let errMsg = String(data: result.stderr, encoding: .utf8) ?? "Sem resposta do smartctl"
            logTelemetry("smartctl em \(deviceNode) falhou (\(String(format: "%.3fs", result.duration))): \(errMsg)", isError: true)
            return SMARTData(temperature: nil, smartPassed: nil, modelName: nil, rawError: errMsg)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] {
            var temp: Int? = nil
            
            // Parse de temperatura (NVMe / ATA)
            if let tempDict = json["temperature"] as? [String: Any],
               let current = tempDict["current"] as? Int {
                temp = current
            } else if let nvmeLog = json["nvme_smart_health_information_log"] as? [String: Any],
                          let current = nvmeLog["temperature"] as? Int {
                temp = current
            }
            
            // Parse de status SMART
            var passed: Bool? = nil
            if let statusDict = json["smart_status"] as? [String: Any],
               let p = statusDict["passed"] as? Bool {
                passed = p
            }
            
            let model = json["model_name"] as? String
            
            logTelemetry("SMART lido em \(String(format: "%.3fs", result.duration)): Temp = \(temp?.description ?? "N/A")°C | Status = \(passed?.description ?? "N/A") | Modelo = \(model ?? "N/A")")
            
            return SMARTData(
                temperature: temp,
                smartPassed: passed,
                modelName: model,
                rawError: nil
            )
        }
        
        logTelemetry("Falha ao deserializar JSON do smartctl", isError: true)
        return SMARTData(temperature: nil, smartPassed: nil, modelName: nil, rawError: "Falha ao deserializar JSON do SMART")
    }
    
    /// Executa lsof ultrarrápido em background (<0.15s) com logging
    public func fetchActiveProcesses(volumePath: String) async -> [ActiveProcess] {
        guard FileManager.default.fileExists(atPath: volumePath) else {
            return []
        }
        
        logTelemetry("Executando lsof em \(volumePath)...")
        let result = await runSubprocess(executable: "/usr/sbin/lsof", arguments: ["-w", "-F", "pcn", volumePath], timeoutSeconds: 1.5)
        
        guard let output = String(data: result.stdout, encoding: .utf8), !output.isEmpty else {
            logTelemetry("lsof concluído em \(String(format: "%.3fs", result.duration)): Nenhum processo ativo retornado.")
            return []
        }
        
        let processes = parseLsofOutput(output)
        logTelemetry("lsof concluído em \(String(format: "%.3fs", result.duration)): \(processes.count) processo(s) ativo(s) localizado(s).")
        for proc in processes {
            logTelemetry("  ↳ PID \(proc.pid) [\(proc.name)]: \(proc.openFiles.count) arquivo(s) aberto(s)")
        }
        
        return processes
    }
    
    private func parseLsofOutput(_ output: String) -> [ActiveProcess] {
        var processDict: [pid_t: (name: String, openFiles: Set<String>)] = [:]
        var currentPID: pid_t?
        var currentName: String = "Desconhecido"
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            guard let firstChar = line.first else { continue }
            let value = String(line.dropFirst())
            
            switch firstChar {
            case "p":
                if let pid = pid_t(value) {
                    currentPID = pid
                    if processDict[pid] == nil {
                        processDict[pid] = (name: currentName, openFiles: [])
                    }
                }
            case "c":
                currentName = value
                if let pid = currentPID {
                    let existingFiles = processDict[pid]?.openFiles ?? []
                    processDict[pid] = (name: currentName, openFiles: existingFiles)
                }
            case "n":
                if let pid = currentPID, !value.isEmpty {
                    processDict[pid]?.openFiles.insert(value)
                }
            default:
                break
            }
        }
        
        return processDict.map { (pid, info) in
            ActiveProcess(
                pid: pid,
                name: info.name,
                openFiles: Array(info.openFiles).sorted()
            )
        }.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
    }
    
    /// Obtém estatísticas de armazenamento usado/livre
    public nonisolated func fetchStorageInfo(volumePath: String) -> StorageInfo? {
        let url = URL(fileURLWithPath: volumePath)
        guard FileManager.default.fileExists(atPath: volumePath) else { return nil }
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            let storage = StorageInfo(totalBytes: total, freeBytes: free)
            logTelemetry("Espaço em \(volumePath): Total = \(storage.totalBytes / 1_073_741_824)GB | Livre = \(storage.freeBytes / 1_073_741_824)GB (\(String(format: "%.1f", storage.usedRatio * 100))% usado)")
            return storage
        } catch {
            logTelemetry("Erro ao ler atributos de armazenamento de \(volumePath): \(error.localizedDescription)", isError: true)
            return nil
        }
    }
    
    /// Encerra um processo pelo PID (SIGTERM / SIGKILL)
    public func killProcess(pid: pid_t) async -> Bool {
        logTelemetry("Solicitado encerramento do processo PID: \(pid)...")
        let result = kill(pid, SIGTERM)
        if result == 0 {
            logTelemetry("Processo PID \(pid) encerrado com SIGTERM.")
            return true
        }
        logTelemetry("SIGTERM falhou para PID \(pid). Tentando SIGKILL...", isError: true)
        let forceResult = kill(pid, SIGKILL)
        if forceResult == 0 {
            logTelemetry("Processo PID \(pid) forçado a encerrar com SIGKILL.")
            return true
        }
        logTelemetry("Falha ao encerrar processo PID \(pid) com SIGKILL.", isError: true)
        return false
    }
    
    /// Ejeta o volume usando NSWorkspace
    public func unmountVolume(at volumePath: String) async throws {
        logTelemetry("Iniciando ejeção segura de \(volumePath)...")
        let url = URL(fileURLWithPath: volumePath)
        let workspace = NSWorkspace.shared
        try workspace.unmountAndEjectDevice(at: url)
        logTelemetry("Volume \(volumePath) ejetado com sucesso!")
    }
}
