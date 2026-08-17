//
//  DiskWatcher.swift
//  SSDMonitor
//
//  Gerenciador do estado de conexão, montagem e timer de polling com logging.
//

import Foundation
import AppKit
import Combine


// MARK: - Domain Models: Thermal Telemetry & History

public enum ThermalLevel: String, Sendable, Comparable, CaseIterable {
    case normal
    case warm
    case throttling
    case critical

    private var order: Int {
        switch self {
        case .normal: return 0
        case .warm: return 1
        case .throttling: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.order < rhs.order
    }

    public var title: String {
        switch self {
        case .normal: return "Temperatura Normal"
        case .warm: return "Temperatura Elevada"
        case .throttling: return "Thermal Throttling"
        case .critical: return "Superaquecimento!"
        }
    }

    public var shortBadgeTitle: String {
        switch self {
        case .normal: return "Saudável"
        case .warm: return "Aquecido"
        case .throttling: return "Throttling"
        case .critical: return "Perigo"
        }
    }
}

public struct ThermalStatus: Sendable, Equatable {
    public let temperature: Int?
    public let controllerTemp: Int?
    public let nandTemp: Int?
    public let level: ThermalLevel
    public let isThrottling: Bool
    public let statusText: String
    public let subtitleText: String

    public init(
        temperature: Int?,
        controllerTemp: Int? = nil,
        nandTemp: Int? = nil,
        level: ThermalLevel = .normal,
        isThrottling: Bool = false,
        statusText: String = "N/A",
        subtitleText: String = ""
    ) {
        self.temperature = temperature
        self.controllerTemp = controllerTemp
        self.nandTemp = nandTemp
        self.level = level
        self.isThrottling = isThrottling
        self.statusText = statusText
        self.subtitleText = subtitleText
    }

    public init(temperature: Int?, sensors: [Int]?) {
        self = Self.evaluate(temperature: temperature, sensors: sensors)
    }

    public static func evaluate(temperature: Int?, sensors: [Int]?) -> ThermalStatus {
        guard let temp = temperature else {
            return ThermalStatus(
                temperature: nil,
                controllerTemp: nil,
                nandTemp: nil,
                level: .normal,
                isThrottling: false,
                statusText: "Temperatura N/A",
                subtitleText: "Aguardando leitura de telemetria"
            )
        }

        let ctrlTemp = sensors?.first
        let nandTemp = (sensors?.count ?? 0) >= 2 ? sensors?[1] : nil
        let effectiveTemp = max(temp, ctrlTemp ?? temp)

        let isThrottling = effectiveTemp >= 70
        let level: ThermalLevel
        let statusText: String
        let subtitleText: String

        switch effectiveTemp {
        case ..<55:
            level = .normal
            statusText = "Temperatura Normal"
            subtitleText = "Operando na faixa de temperatura ideal (< 55 °C)"
        case 55..<70:
            level = .warm
            statusText = "Temperatura Elevada"
            subtitleText = "Dissipação sob carga ativa em case passivo (55 °C – 69 °C)"
        case 70..<75:
            level = .throttling
            statusText = "Thermal Throttling Ativo"
            subtitleText = "Controladora atingiu gatilho térmico (70 °C – 74 °C). Desempenho reduzido."
        default:
            level = .critical
            statusText = "Superaquecimento Severo!"
            subtitleText = "Temperatura crítica (≥ 75 °C). Risco de desligamento térmico (~85 °C)."
        }

        return ThermalStatus(
            temperature: temp,
            controllerTemp: ctrlTemp,
            nandTemp: nandTemp,
            level: level,
            isThrottling: isThrottling,
            statusText: statusText,
            subtitleText: subtitleText
        )
    }
}

public struct TemperatureReading: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let temperature: Int
    public let controllerTemp: Int?
    public let nandTemp: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        temperature: Int,
        controllerTemp: Int? = nil,
        nandTemp: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.temperature = temperature
        self.controllerTemp = controllerTemp
        self.nandTemp = nandTemp
    }
}

@MainActor
public final class DiskWatcher: ObservableObject {
    // MARK: - Published Properties
    
    @Published public var isMounted: Bool = false
    @Published public var isInserted: Bool = true
    @Published public var targetVolume: TargetVolume = TargetVolume()
    
    public var targetVolumeName: String { targetVolume.name }
    public var targetMountPoint: String {
        get { targetVolume.mountPoint }
        set { targetVolume = TargetVolume(name: targetVolume.name, mountPoint: newValue, bsdNode: targetVolume.bsdNode) }
    }
    public var bsdIdentifier: String {
        get { targetVolume.bsdNode }
        set { targetVolume = targetVolume.updatingBSDNode(newValue) }
    }
    
    @Published public var temperature: Int? = nil
    @Published public var temperatureSensors: [Int]? = nil
    @Published public var temperatureHistory: [TemperatureReading] = []
    @Published public var smartPassed: Bool? = nil
    @Published public var modelName: String? = nil
    @Published public var rawSmartError: String? = nil
    @Published public var storageInfo: StorageInfo? = nil
    @Published public var activeProcesses: [ActiveProcess] = []
    @Published public var availableVolumes: [TargetVolume] = []
    
    public var thermalStatus: ThermalStatus {
        ThermalStatus.evaluate(temperature: temperature, sensors: temperatureSensors)
    }
    
    public var isThrottling: Bool {
        thermalStatus.isThrottling
    }
    
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date? = nil
    @Published public var errorMessage: String? = nil
    @Published public var statusMessage: String? = nil
    @Published public var isEjecting: Bool = false
    
    private let savedVolumeKey = "SelectedTargetVolumeName"
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    private let telemetry: TelemetryProvider
    public var volumeLister: @Sendable () -> [TargetVolume]

    // MARK: - Initialization

    public init(
        telemetry: TelemetryProvider = TelemetryService.shared,
        volumeLister: @escaping @Sendable () -> [TargetVolume] = { MainActor.assumeIsolated { TargetVolume.listMountedExternalVolumes() } }
    ) {
        self.telemetry = telemetry
        self.volumeLister = volumeLister

        if let savedName = UserDefaults.standard.string(forKey: savedVolumeKey) {
            self.targetVolume = TargetVolume(name: savedName)
        } else {
            self.targetVolume = TargetVolume()
        }

        setupMountObservers()
        updateAvailableVolumes()
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
    
    // MARK: - Volume Discovery & Selection
    
    public func updateAvailableVolumes() {
        let mounted = volumeLister()
        self.availableVolumes = mounted
        
        if !targetVolume.isMounted, let firstAvailable = mounted.first(where: { $0.isMounted }) {
            selectVolume(firstAvailable)
        }
    }
    
    public func selectVolume(_ volume: TargetVolume) {
        logWatcher("Volume selecionado: \(volume.name) (\(volume.mountPoint))")
        self.targetVolume = volume
        UserDefaults.standard.set(volume.name, forKey: savedVolumeKey)
        self.temperatureHistory = []
        self.statusMessage = nil
        self.errorMessage = nil
        refreshAll()
    }
    
    // MARK: - Core Refresh Pipeline
    
    public func refreshAll() {
        updateAvailableVolumes()
        let exists = targetVolume.isMounted
        self.isMounted = exists
        
        guard exists else {
            logWatcher("Volume \(targetMountPoint) NÃO está montado.", isError: true)
            self.temperature = nil
            self.temperatureSensors = nil
            self.temperatureHistory = []
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
        
        guard !isRefreshing && !isEjecting else {
            logWatcher("Refresh ignorado: ejeção ou ciclo de atualização anterior em andamento.")
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
            
            let initialTarget = await MainActor.run { [weak self] in self?.targetVolume ?? TargetVolume() }
            let detectedNode = await telemetry.detectBSDNode(for: initialTarget)
            let currentTarget = await MainActor.run { [weak self] () -> TargetVolume in
                guard let self = self else { return initialTarget }
                let updated = self.targetVolume.updatingBSDNode(detectedNode)
                self.targetVolume = updated
                return updated
            }
            
            // 2. Telemetria de Armazenamento (Instantâneo)
            let storage = telemetry.fetchStorageInfo(for: currentTarget)
            
            // 3. SMART & Temperatura (Instantâneo < 0.05s)
            let smart = await telemetry.fetchSMARTData(for: currentTarget)
            
            // Atualiza IMEDIATAMENTE a temperatura na UI
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.bsdIdentifier = detectedNode
                self.storageInfo = storage
                self.temperature = smart.temperature
                self.temperatureSensors = smart.temperatureSensors
                if let temp = smart.temperature {
                    let reading = TemperatureReading(
                        timestamp: Date(),
                        temperature: temp,
                        controllerTemp: smart.temperatureSensors?.first,
                        nandTemp: (smart.temperatureSensors?.count ?? 0) >= 2 ? smart.temperatureSensors?[1] : nil
                    )
                    self.temperatureHistory.append(reading)
                    if self.temperatureHistory.count > 60 {
                        self.temperatureHistory.removeFirst(self.temperatureHistory.count - 60)
                    }
                }
                self.smartPassed = smart.smartPassed
                self.modelName = smart.modelName
                self.rawSmartError = smart.rawError
                self.lastUpdated = Date()
                logWatcher("UI atualizada: Temp = \(smart.temperature?.description ?? "N/A")°C | Node = \(detectedNode)")
            }
            // 4. Processos Ativos via lsof (Com timeout curto)
            let procs = await telemetry.fetchActiveProcesses(for: currentTarget)
            
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
    
    public func ejectVolume(force: Bool = false) {
        guard isMounted else { return }
        stopTimer() // Interrompe o polling de background durante a ejeção
        isEjecting = true
        errorMessage = nil
        let actionMsg = force ? "Forçando ejeção de" : "Tentando ejetar"
        statusMessage = "\(actionMsg) \(targetVolumeName)..."
        logWatcher("Comando recebido: Ejetar volume \(targetVolumeName) (force: \(force))...")
        
        // Garante que o diretório de trabalho do processo esteja em '/'
        FileManager.default.changeCurrentDirectoryPath("/")
        
        Task {
            // Aguarda o encerramento de qualquer ciclo prévio de refresh de telemetria
            while self.isRefreshing {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            
            do {
                try await self.telemetry.unmountVolume(at: self.targetVolume, force: force)
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
                    self.errorMessage = error.localizedDescription
                    logWatcher("Erro ao ejetar volume: \(error.localizedDescription)", isError: true)
                    self.startTimer() // Reinicia o polling se a ejeção falhar
                    self.refreshAll()
                }
            }
        }
    }
}
