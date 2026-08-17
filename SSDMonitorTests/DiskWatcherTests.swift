//
//  DiskWatcherTests.swift
//  SSDMonitorTests
//
//  Testes unitários para a máquina de estados do DiskWatcher com MockTelemetryProvider.
//

import Testing
import Foundation
@testable import SSDMonitor

@MainActor
struct DiskWatcherTests {

    @Test func testDiskWatcher_MountedVolume_PopulatesTelemetryState() async throws {
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("MountedSSD_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let mockTelemetry = MockTelemetryProvider()
        mockTelemetry.bsdNodeToReturn = "/dev/disk9"
        mockTelemetry.smartDataToReturn = SMARTData(temperature: 42, smartPassed: true, modelName: "Mock Samsung SSD", rawError: nil)
        mockTelemetry.storageInfoToReturn = StorageInfo(totalBytes: 1_000_000_000_000, freeBytes: 500_000_000_000)
        mockTelemetry.activeProcessesToReturn = [
            ActiveProcess(pid: 999, name: "Final Cut Pro", openFiles: ["/file.mov"])
        ]

        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer() // Parar o timer de polling automático para controle determinístico do teste
        watcher.targetMountPoint = tempVolume.path

        watcher.refreshAll()

        // Aguarda a conclusão das Tasks assíncronas do refreshAll
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(watcher.isMounted == true)
        #expect(watcher.bsdIdentifier == "/dev/disk9")
        #expect(watcher.temperature == 42)
        #expect(watcher.smartPassed == true)
        #expect(watcher.modelName == "Mock Samsung SSD")
        #expect(watcher.activeProcesses.count == 1)
        #expect(watcher.activeProcesses.first?.name == "Final Cut Pro")
    }

    @Test func testDiskWatcher_UnmountedVolume_ResetsStateAndSetsStatusMessage() async throws {
        let mockTelemetry = MockTelemetryProvider()
        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer()
        watcher.targetMountPoint = "/Volumes/NonExistentDisk_\(UUID().uuidString)"

        watcher.refreshAll()

        #expect(watcher.isMounted == false)
        #expect(watcher.temperature == nil)
        #expect(watcher.smartPassed == nil)
        #expect(watcher.storageInfo == nil)
        #expect(watcher.activeProcesses.isEmpty == true)
        #expect(watcher.statusMessage == "Volume desconectado ou não montado")
    }

    @Test func testDiskWatcher_SafeEjectionSuccess_UpdatesStatusMessage() async throws {
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("EjectSSD_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let mockTelemetry = MockTelemetryProvider()
        mockTelemetry.unmountShouldFail = false
        mockTelemetry.onUnmount = { path in
            try? FileManager.default.removeItem(atPath: path)
        }
        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer()
        watcher.targetMountPoint = tempVolume.path
        watcher.refreshAll()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(watcher.isMounted == true)

        watcher.ejectVolume()

        // Aguarda a Task assíncrona de ejeção
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(watcher.isEjecting == false)
        #expect(watcher.errorMessage == nil)
        #expect(watcher.statusMessage?.contains("ejetado com segurança") == true)
    }

    @Test func testDiskWatcher_SafeEjectionFailure_SetsErrorMessageAndRecovers() async throws {
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("FailedEjectSSD_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let mockTelemetry = MockTelemetryProvider()
        mockTelemetry.unmountShouldFail = true

        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer()
        watcher.targetMountPoint = tempVolume.path
        watcher.refreshAll()

        try await Task.sleep(nanoseconds: 50_000_000)

        watcher.ejectVolume()

        // Aguarda a Task assíncrona de ejeção com falha
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(watcher.isEjecting == false)
        #expect(watcher.errorMessage != nil)
    }

    @Test func testDiskWatcher_KillProcessSuccess_SetsStatusMessage() async throws {
        let mockTelemetry = MockTelemetryProvider()
        mockTelemetry.killResultToReturn = true

        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer()

        watcher.killProcess(pid: 1234)

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(watcher.statusMessage == "Processo 1234 encerrado com sucesso.")
        #expect(watcher.errorMessage == nil)
    }
    @Test func testDiskWatcher_VolumeDiscovery_ListsAndSelectsAvailableVolumes() async throws {
        let volA = TargetVolume(name: "VolumeA", mountPoint: "/Volumes/VolumeA", bsdNode: "/dev/disk5")
        let volB = TargetVolume(name: "VolumeB", mountPoint: "/Volumes/VolumeB", bsdNode: "/dev/disk6")
        let mockTelemetry = MockTelemetryProvider()

        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [volA, volB] })
        watcher.stopTimer()

        #expect(watcher.availableVolumes.count == 2)
        #expect(watcher.availableVolumes == [volA, volB])

        watcher.selectVolume(volB)
        #expect(watcher.targetVolume == volB)
        #expect(watcher.targetMountPoint == "/Volumes/VolumeB")
    }

    @Test func testThermalStatus_LevelsAndThrottling() {
        let statusNormal = ThermalStatus(temperature: 45, sensors: nil)
        #expect(statusNormal.level == .normal)
        #expect(statusNormal.isThrottling == false)
        #expect(statusNormal.statusText == "Temperatura Normal")

        let statusWarm = ThermalStatus(temperature: 62, sensors: nil)
        #expect(statusWarm.level == .warm)
        #expect(statusWarm.isThrottling == false)
        #expect(statusWarm.statusText == "Temperatura Elevada")

        let statusThrottling = ThermalStatus(temperature: 70, sensors: [70, 72])
        #expect(statusThrottling.level == .throttling)
        #expect(statusThrottling.isThrottling == true)
        #expect(statusThrottling.statusText == "Thermal Throttling Ativo")

        let statusCritical = ThermalStatus(temperature: 78, sensors: [78])
        #expect(statusCritical.level == .critical)
        #expect(statusCritical.isThrottling == true)
        #expect(statusCritical.statusText == "Superaquecimento Severo!")
    }
    @Test func testTemperatureHistory_AccumulatesAndCapsAt60Readings() async throws {
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("MountedSSD_History_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let mockTelemetry = MockTelemetryProvider()
        mockTelemetry.bsdNodeToReturn = "/dev/disk9"
        mockTelemetry.smartDataToReturn = SMARTData(temperature: 40, smartPassed: true, modelName: "Mock NVMe", rawError: nil)

        let watcher = DiskWatcher(telemetry: mockTelemetry, volumeLister: { [] })
        watcher.stopTimer()
        watcher.targetMountPoint = tempVolume.path

        for i in 1...65 {
            mockTelemetry.smartDataToReturn = SMARTData(temperature: 40 + (i % 30), smartPassed: true, modelName: "Mock NVMe", rawError: nil)
            watcher.refreshAll()
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        #expect(watcher.temperatureHistory.count == 60)
        #expect(watcher.temperatureHistory.last?.temperature == watcher.temperature)
    }
}
