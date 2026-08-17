//
//  TelemetryService.swift
//  SSDMonitor
//
//  Executor assíncrono de subprocessos (smartctl, lsof, diskutil unmount) com logging.
//

import Foundation
import AppKit


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
    public let temperatureSensors: [Int]?

    public nonisolated init(temperature: Int?, smartPassed: Bool?, modelName: String?, rawError: String? = nil, temperatureSensors: [Int]? = nil) {
        self.temperature = temperature
        self.smartPassed = smartPassed
        self.modelName = modelName
        self.rawError = rawError
        self.temperatureSensors = temperatureSensors
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
            var sensors: [Int]? = nil
            
            // Parse de temperatura (NVMe / ATA)
            if let tempDict = json["temperature"] as? [String: Any],
               let current = tempDict["current"] as? Int {
                temp = current
            } else if let nvmeLog = json["nvme_smart_health_information_log"] as? [String: Any],
                          let current = nvmeLog["temperature"] as? Int {
                temp = current
            }
            
            if let nvmeLog = json["nvme_smart_health_information_log"] as? [String: Any],
               let sensorList = nvmeLog["temperature_sensors"] as? [Int] {
                sensors = sensorList
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
                rawError: nil,
                temperatureSensors: sensors
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
            let errStr = String(data: result.stderr, encoding: .utf8) ?? ""
            logTelemetry("lsof concluído em \(String(format: "%.3fs", result.duration)) (exitCode \(result.exitCode)): Nenhum processo retornado. stderr: '\(errStr)'")
            return []
        }
        
        logTelemetry("lsof raw output:\n\(output)")
        let processes = parseLsofOutput(output)
        logTelemetry("lsof concluído em \(String(format: "%.3fs", result.duration)): \(processes.count) processo(s) filtrado(s) localizado(s).")
        for proc in processes {
            logTelemetry("  ↳ PID \(proc.pid) [\(proc.name)]: \(proc.openFiles.count) arquivo(s) aberto(s) -> \(proc.openFiles)")
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
                    currentName = "Desconhecido"
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
        
        let currentAppPID = ProcessInfo.processInfo.processIdentifier
        let ignoredNames: Set<String> = ["ssdmonitor", "lsof", "smartctl", "diskutil"]
        
        return processDict.compactMap { (pid, info) in
            if pid == currentAppPID || ignoredNames.contains(info.name.lowercased()) {
                return nil
            }
            return ActiveProcess(
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
    /// Ejeta o volume usando diskutil eject (com fallback para unmount e NSWorkspace)
    public func unmountVolume(at volumePath: String, force: Bool = false) async throws {
        logTelemetry("Iniciando ejeção (forçada: \(force)) de \(volumePath)...")
        
        if force {
            logTelemetry("Executando diskutil eject force \(volumePath)...")
            let result = await runSubprocess(executable: "/usr/sbin/diskutil", arguments: ["eject", "force", volumePath], timeoutSeconds: 5.0)
            if result.exitCode == 0 {
                logTelemetry("Volume \(volumePath) ejetado forçadamente via diskutil com sucesso!")
                return
            }
            let unmountForceResult = await runSubprocess(executable: "/usr/sbin/diskutil", arguments: ["unmount", "force", volumePath], timeoutSeconds: 5.0)
            if unmountForceResult.exitCode == 0 {
                logTelemetry("Volume \(volumePath) desmontado forçadamente via diskutil unmount force!")
                return
            }
            
            let errOutput = String(data: result.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (errOutput != nil && !errOutput!.isEmpty) ? errOutput! : "Falha ao forçar ejeção."
            logTelemetry("Ejeção forçada falhou (\(result.exitCode)): \(detail)", isError: true)
            throw NSError(
                domain: "SSDMonitor.TelemetryService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "Falha ao ejetar forçadamente: \(detail)"]
            )
        }
        
        // 1. Tenta primariamente via CLI `diskutil eject` (comunicação direta com diskarbitrationd)
        logTelemetry("Executando diskutil eject \(volumePath)...")
        let diskutilResult = await runSubprocess(executable: "/usr/sbin/diskutil", arguments: ["eject", volumePath], timeoutSeconds: 5.0)
        let ejectStdout = String(data: diskutilResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ejectStderr = String(data: diskutilResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        logTelemetry("diskutil eject res (code \(diskutilResult.exitCode)): stdout='\(ejectStdout)', stderr='\(ejectStderr)'")
        if diskutilResult.exitCode == 0 {
            logTelemetry("Volume \(volumePath) ejetado via diskutil eject com sucesso!")
            return
        }
        
        // 2. Secundariamente tenta via `diskutil unmount`
        logTelemetry("diskutil eject retornou \(diskutilResult.exitCode). Tentando diskutil unmount \(volumePath)...")
        let unmountResult = await runSubprocess(executable: "/usr/sbin/diskutil", arguments: ["unmount", volumePath], timeoutSeconds: 5.0)
        let unmountStdout = String(data: unmountResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unmountStderr = String(data: unmountResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        logTelemetry("diskutil unmount res (code \(unmountResult.exitCode)): stdout='\(unmountStdout)', stderr='\(unmountStderr)'")
        if unmountResult.exitCode == 0 {
            logTelemetry("Volume \(volumePath) desmontado via diskutil unmount com sucesso!")
            return
        }
        // 3. Terciariamente tenta via NSWorkspace Cocoa API
        let url = URL(fileURLWithPath: volumePath)
        let workspace = NSWorkspace.shared
        do {
            try workspace.unmountAndEjectDevice(at: url)
            logTelemetry("Volume \(volumePath) ejetado via NSWorkspace com sucesso!")
            return
        } catch {
            let stderrStr = String(data: diskutilResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (stderrStr != nil && !stderrStr!.isEmpty) ? stderrStr! : error.localizedDescription
            logTelemetry("Ejeção de \(volumePath) falhou em todas as tentativas: \(detail)", isError: true)
            
            let friendlyMessage: String
            if detail.contains("47") || detail.contains("busy") || detail.contains("Dissented") || (error as NSError).code == -47 {
                friendlyMessage = "O volume está sendo usado por processos do sistema ou aplicativos. Encerre os processos ou use a Ejeção Forçada."
            } else {
                friendlyMessage = "Falha ao ejetar volume: \(detail)"
            }
            
            throw NSError(
                domain: "SSDMonitor.TelemetryService",
                code: -47,
                userInfo: [NSLocalizedDescriptionKey: friendlyMessage]
            )
        }
    }
}
