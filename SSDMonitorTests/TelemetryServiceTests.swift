//
//  TelemetryServiceTests.swift
//  SSDMonitorTests
//
//  Testes unitários para o TelemetryService utilizando InMemoryCommandRunner.
//

import Testing
import Foundation
@testable import SSDMonitor

struct TelemetryServiceTests {

    @Test func testFetchSMARTData_NVMeJSON_ParsesTemperatureAndStatus() async throws {
        let jsonString = """
        {
            "model_name": "Samsung SSD 980 PRO 1TB",
            "temperature": { "current": 42 },
            "smart_status": { "passed": true }
        }
        """
        let runner = InMemoryCommandRunner()
        runner.setHandler { executable, arguments in
            if executable.contains("smartctl") {
                return CommandExecutionResult(
                    stdout: jsonString.data(using: .utf8)!,
                    stderr: Data(),
                    exitCode: 0,
                    duration: 0.05
                )
            }
            return CommandExecutionResult(stdout: Data(), stderr: Data(), exitCode: -1, duration: 0.0)
        }

        let telemetry = TelemetryService(commandRunner: runner)
        let smartData = await telemetry.fetchSMARTData(deviceNode: "/dev/disk8")

        #expect(smartData.temperature == 42)
        #expect(smartData.smartPassed == true)
        #expect(smartData.modelName == "Samsung SSD 980 PRO 1TB")
        #expect(smartData.rawError == nil)
    }

    @Test func testFetchSMARTData_NVMeLogFormat_ParsesTemperature() async throws {
        let jsonString = """
        {
            "model_name": "Crucial CT1000P5PSSD8",
            "nvme_smart_health_information_log": { "temperature": 39 },
            "smart_status": { "passed": true }
        }
        """
        let runner = InMemoryCommandRunner()
        runner.setHandler { executable, arguments in
            return CommandExecutionResult(
                stdout: jsonString.data(using: .utf8)!,
                stderr: Data(),
                exitCode: 0,
                duration: 0.02
            )
        }

        let telemetry = TelemetryService(commandRunner: runner)
        let smartData = await telemetry.fetchSMARTData(deviceNode: "/dev/disk8")

        #expect(smartData.temperature == 39)
        #expect(smartData.smartPassed == true)
        #expect(smartData.modelName == "Crucial CT1000P5PSSD8")
    }

    @Test func testFetchSMARTData_EmptyOutput_ReturnsRawError() async throws {
        let runner = InMemoryCommandRunner()
        runner.setHandler { executable, arguments in
            return CommandExecutionResult(
                stdout: Data(),
                stderr: "smartctl: Device open failed".data(using: .utf8)!,
                exitCode: 1,
                duration: 0.01
            )
        }

        let telemetry = TelemetryService(commandRunner: runner)
        let smartData = await telemetry.fetchSMARTData(deviceNode: "/dev/disk8")

        #expect(smartData.temperature == nil)
        #expect(smartData.smartPassed == nil)
        #expect(smartData.rawError == "smartctl: Device open failed")
    }

    @Test func testFetchActiveProcesses_ParsesLsofOutput() async throws {
        let lsofOutput = """
        p1234
        cFinal Cut Pro
        n/Volumes/PauloSSDExterno/Project.fcpbundle/QuickTime.mov
        p5678
        cQuickTime Player
        n/Volumes/PauloSSDExterno/movie.mp4
        """
        let runner = InMemoryCommandRunner()
        runner.setHandler { executable, arguments in
            if executable.contains("lsof") {
                return CommandExecutionResult(
                    stdout: lsofOutput.data(using: .utf8)!,
                    stderr: Data(),
                    exitCode: 0,
                    duration: 0.03
                )
            }
            return CommandExecutionResult(stdout: Data(), stderr: Data(), exitCode: -1, duration: 0.0)
        }

        let telemetry = TelemetryService(commandRunner: runner)
        // Cria um diretório temporário para simular a existência do volumePath no FileManager
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("TestVolume_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let processes = await telemetry.fetchActiveProcesses(volumePath: tempVolume.path)

        #expect(processes.count == 2)
        
        let fcp = processes.first(where: { $0.pid == 1234 })
        #expect(fcp != nil)
        #expect(fcp?.name == "Final Cut Pro")
        #expect(fcp?.openFiles.count == 1)

        let qt = processes.first(where: { $0.pid == 5678 })
        #expect(qt != nil)
        #expect(qt?.name == "QuickTime Player")
    }

    @Test func testDetectBSDNode_ParsesDiskutilPlist() async throws {
        let plistString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ParentWholeDisk</key>
            <string>disk9</string>
            <key>DeviceNode</key>
            <string>/dev/disk9s1</string>
        </dict>
        </plist>
        """
        let runner = InMemoryCommandRunner()
        runner.setHandler { executable, arguments in
            if executable.contains("diskutil") {
                return CommandExecutionResult(
                    stdout: plistString.data(using: .utf8)!,
                    stderr: Data(),
                    exitCode: 0,
                    duration: 0.01
                )
            }
            return CommandExecutionResult(stdout: Data(), stderr: Data(), exitCode: -1, duration: 0.0)
        }

        let telemetry = TelemetryService(commandRunner: runner)
        let tempVolume = FileManager.default.temporaryDirectory.appendingPathComponent("TestVolume_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVolume, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempVolume) }

        let node = await telemetry.detectBSDNode(forVolumePath: tempVolume.path)
        #expect(node == "/dev/disk9")
    }
}
