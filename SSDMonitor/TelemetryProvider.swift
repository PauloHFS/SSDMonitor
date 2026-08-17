//
//  TelemetryProvider.swift
//  SSDMonitor
//
//  Contrato (seam) para fornecimento de dados de telemetria, processos e ejeção de disco.
//

import Foundation

public protocol TelemetryProvider: Sendable {
    func detectBSDNode(for target: TargetVolume) async -> String
    func detectBSDNode(forVolumePath volumePath: String) async -> String
    
    func fetchStorageInfo(for target: TargetVolume) -> StorageInfo?
    func fetchStorageInfo(volumePath: String) -> StorageInfo?
    
    func fetchSMARTData(for target: TargetVolume) async -> SMARTData
    func fetchSMARTData(deviceNode: String) async -> SMARTData
    
    func fetchActiveProcesses(for target: TargetVolume) async -> [ActiveProcess]
    func fetchActiveProcesses(volumePath: String) async -> [ActiveProcess]
    
    func killProcess(pid: pid_t) async -> Bool
    
    func unmountVolume(at target: TargetVolume, force: Bool) async throws
    func unmountVolume(at volumePath: String, force: Bool) async throws
}

public extension TelemetryProvider {
    func detectBSDNode(for target: TargetVolume) async -> String {
        await detectBSDNode(forVolumePath: target.mountPoint)
    }
    
    func fetchStorageInfo(for target: TargetVolume) -> StorageInfo? {
        fetchStorageInfo(volumePath: target.mountPoint)
    }
    
    func fetchSMARTData(for target: TargetVolume) async -> SMARTData {
        await fetchSMARTData(deviceNode: target.bsdNode)
    }
    
    func fetchActiveProcesses(for target: TargetVolume) async -> [ActiveProcess] {
        await fetchActiveProcesses(volumePath: target.mountPoint)
    }
    
    func unmountVolume(at target: TargetVolume, force: Bool = false) async throws {
        try await unmountVolume(at: target.mountPoint, force: force)
    }
    func unmountVolume(at volumePath: String) async throws {
        try await unmountVolume(at: volumePath, force: false)
    }
}

extension TelemetryService: TelemetryProvider {}

/// Provedor mock de telemetria para testes unitários e pré-visualizações do SwiftUI.
public final class MockTelemetryProvider: TelemetryProvider, @unchecked Sendable {
    public var bsdNodeToReturn: String = "/dev/disk8"
    public var storageInfoToReturn: StorageInfo? = StorageInfo(totalBytes: 1_000_000_000_000, freeBytes: 400_000_000_000)
    public var smartDataToReturn: SMARTData = SMARTData(temperature: 36, smartPassed: true, modelName: "Mock SSD 1TB", rawError: nil)
    public var activeProcessesToReturn: [ActiveProcess] = []
    public var killResultToReturn: Bool = true
    public var unmountShouldFail: Bool = false
    public var unmountErrorToThrow: Error = NSError(
        domain: "MockTelemetryProvider",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Falha simulada ao ejetar volume"]
    )
    public var onUnmount: ((String) -> Void)?

    public init() {}

    public func detectBSDNode(forVolumePath volumePath: String) async -> String {
        return bsdNodeToReturn
    }

    public func fetchStorageInfo(volumePath: String) -> StorageInfo? {
        return storageInfoToReturn
    }

    public func fetchSMARTData(deviceNode: String) async -> SMARTData {
        return smartDataToReturn
    }

    public func fetchActiveProcesses(volumePath: String) async -> [ActiveProcess] {
        return activeProcessesToReturn
    }

    public func killProcess(pid: pid_t) async -> Bool {
        return killResultToReturn
    }

    public func unmountVolume(at volumePath: String, force: Bool = false) async throws {
        onUnmount?(volumePath)
        if unmountShouldFail {
            throw unmountErrorToThrow
        }
    }
}
