//
//  TelemetryProvider.swift
//  SSDMonitor
//
//  Contrato (seam) para fornecimento de dados de telemetria, processos e ejeção de disco.
//

import Foundation

/// Interface de abstração do serviço de telemetria e gerenciamento de processos/ejeção de disco.
public protocol TelemetryProvider: Sendable {
    func detectBSDNode(forVolumePath volumePath: String) async -> String
    func fetchStorageInfo(volumePath: String) -> StorageInfo?
    func fetchSMARTData(deviceNode: String) async -> SMARTData
    func fetchActiveProcesses(volumePath: String) async -> [ActiveProcess]
    func killProcess(pid: pid_t) async -> Bool
    func unmountVolume(at volumePath: String) async throws
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

    public func unmountVolume(at volumePath: String) async throws {
        onUnmount?(volumePath)
        if unmountShouldFail {
            throw unmountErrorToThrow
        }
    }
}
