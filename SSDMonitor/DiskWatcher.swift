//
//  DiskWatcher.swift
//  SSDMonitor
//
//  Gerenciador do estado de conexão, montagem e timer de polling com logging.
//

import Foundation
import AppKit
import Combine

// MARK: - Logger Helper

public nonisolated func logWatcher(_ message: String, isError: Bool = false) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timeStr = formatter.string(from: Date())
    let icon = isError ? "⚠️" : "📊"
    print("[\(timeStr)] [DiskWatcher] \(icon) \(message)")
    fflush(stdout)
}

@MainActor
public final class DiskWatcher: ObservableObject {
    // MARK: - Published Properties
    
    @Published public var isMounted: Bool = false
    @Published public var isInserted: Bool = true
    @Published public var targetVolumeName: String = "PauloSSDExterno"
    @Published public var targetMountPoint: String = "/Volumes/PauloSSDExterno"
    @Published public var bsdIdentifier: String = "/dev/disk8"
    
    @Published public var temperature: Int? = nil
    @Published public var smartPassed: Bool? = nil
    @Published public var modelName: String? = nil
    @Published public var rawSmartError: String? = nil
    
    @Published public var storageInfo: StorageInfo? = nil
    @Published public var activeProcesses: [ActiveProcess] = []
    
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date? = nil
    @Published public var errorMessage: String? = nil
    @Published public var statusMessage: String? = nil
    @Published public var isEjecting: Bool = false
    
    // MARK: - Private Properties
    
    private var timer: Timer?
 private var notificationObservers: [NSObjectProtocol] = []
 private let telemetry: TelemetryProvider
 
 // MARK: - Initialization
 
 public init(telemetry: TelemetryProvider = TelemetryService.shared) {
    self.telemetry = telemetry
        // Garante que o diretório de trabalho (CWD) do processo seja o diretório raiz '/',
        // evitando que o próprio SSDMonitor segure o vnode do volume externo e bloqueie a ejeção.
        FileManager.default.changeCurrentDirectoryPath("/")
        logWatcher("Inicializando DiskWatcher para target: \(targetMountPoint)")
        setupMountObservers()
        refreshAll()
        startTimer()
    }
    
    deinit {
        logWatcher("Finalizando DiskWatcher.")
        timer?.invalidate()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Lifecycle Notifications
    
    private func setupMountObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        logWatcher("Registrando observadores de montagem NSWorkspace...")
        
        let mountObs = wsCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let userInfo = note.userInfo
            let path = (userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? ""
            logWatcher("Notificação recebida: NSWorkspace.didMountNotification (\(path))")
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
        
        let unmountObs = wsCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let userInfo = note.userInfo
            let path = (userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? ""
            logWatcher("Notificação recebida: NSWorkspace.didUnmountNotification (\(path))")
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
        
        notificationObservers.append(contentsOf: [mountObs, unmountObs])
    }
    
    // MARK: - Timer Polling
    
    public func startTimer(interval: TimeInterval = 5.0) {
        stopTimer()
        logWatcher("Iniciando timer de polling com intervalo de \(interval)s...")
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
    }
    
    public func stopTimer() {
        if timer != nil {
            logWatcher("Parando timer de polling.")
            timer?.invalidate()
            timer = nil
        }
    }
    
    // MARK: - Core Refresh Pipeline
    
    public func refreshAll() {
        let exists = FileManager.default.fileExists(atPath: targetMountPoint)
        self.isMounted = exists
        
        guard exists else {
            logWatcher("Volume \(targetMountPoint) NÃO está montado.", isError: true)
            self.temperature = nil
            self.smartPassed = nil
            self.modelName = nil
            self.rawSmartError = nil
            self.storageInfo = nil
            self.activeProcesses = []
            if self.statusMessage == nil {
                self.statusMessage = "Volume desconectado ou não montado"
            }
            return
        }
        
        guard !isRefreshing else {
            logWatcher("Refresh ignorado: ciclo de atualização anterior ainda em andamento.")
            return
        }
        self.isRefreshing = true
        self.statusMessage = nil
        logWatcher("Iniciando ciclo de atualização de telemetria em background...")
        
        Task {
            defer {
                Task { @MainActor [weak self] in
                    self?.isRefreshing = false
                }
            }
            
            let telemetry = self.telemetry
            
            // 1. Identificador Físico Alvo (Detectado dinamicamente via diskutil info)
            let detectedNode = await telemetry.detectBSDNode(forVolumePath: targetMountPoint)
            
            // 2. Telemetria de Armazenamento (Instantâneo)
            let storage = telemetry.fetchStorageInfo(volumePath: targetMountPoint)
            
            // 3. SMART & Temperatura (Instantâneo < 0.05s)
            let smart = await telemetry.fetchSMARTData(deviceNode: detectedNode)
            
            // Atualiza IMEDIATAMENTE a temperatura na UI
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.bsdIdentifier = detectedNode
                self.storageInfo = storage
                self.temperature = smart.temperature
                self.smartPassed = smart.smartPassed
                self.modelName = smart.modelName
                self.rawSmartError = smart.rawError
                self.lastUpdated = Date()
                logWatcher("UI atualizada: Temp = \(smart.temperature?.description ?? "N/A")°C | Node = \(detectedNode)")
            }
            
            // 4. Processos Ativos via lsof (Com timeout curto)
            let procs = await telemetry.fetchActiveProcesses(volumePath: targetMountPoint)
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.activeProcesses = procs
                logWatcher("Ciclo de atualização de telemetria concluído. (\(procs.count) processo(s) ativo(s))")
            }
        }
    }
    
    // MARK: - Actions
    
    public func killProcess(pid: pid_t) {
        logWatcher("Comando recebido: Encerrar PID \(pid)...")
        Task {
            let success = await self.telemetry.killProcess(pid: pid)
            if success {
                self.statusMessage = "Processo \(pid) encerrado com sucesso."
                self.errorMessage = nil
                logWatcher("Processo PID \(pid) encerrado com sucesso.")
            } else {
                self.errorMessage = "Falha ao encerrar o processo \(pid)."
                logWatcher("Falha ao encerrar processo PID \(pid).", isError: true)
            }
            self.refreshAll()
        }
    }
    
    public func ejectVolume() {
        guard isMounted else { return }
        stopTimer() // Interrompe o polling de background durante a ejeção
        isEjecting = true
        errorMessage = nil
        statusMessage = "Tentando ejetar \(targetVolumeName)..."
        logWatcher("Comando recebido: Ejetar volume \(targetVolumeName)...")
        
        // Garante que o diretório de trabalho do processo esteja em '/'
        FileManager.default.changeCurrentDirectoryPath("/")
        
        Task {
            do {
                try await self.telemetry.unmountVolume(at: targetMountPoint)
                await MainActor.run {
                    self.isMounted = false
                    self.isEjecting = false
                    self.statusMessage = "Volume \(targetVolumeName) ejetado com segurança."
                    logWatcher("Ejeção concluída com sucesso!")
                    self.refreshAll()
                }
            } catch {
                await MainActor.run {
                    self.isEjecting = false
                    self.errorMessage = "Erro ao ejetar: \(error.localizedDescription)"
                    logWatcher("Erro ao ejetar volume: \(error.localizedDescription)", isError: true)
                    self.startTimer() // Reinicia o polling se a ejeção falhar
                    self.refreshAll()
                }
            }
        }
    }
}
