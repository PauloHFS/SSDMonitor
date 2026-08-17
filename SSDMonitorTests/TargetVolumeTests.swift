//
//  TargetVolumeTests.swift
//  SSDMonitorTests
//
//  Testes unitários para o objeto de valor TargetVolume.
//

import Testing
import Foundation
@testable import SSDMonitor

struct TargetVolumeTests {

    @Test func testDefaultInitialization() {
        let volume = TargetVolume()
        #expect(volume.name == "PauloSSDExterno")
        #expect(volume.mountPoint == "/Volumes/PauloSSDExterno")
        #expect(volume.bsdNode == "/dev/disk8")
        #expect(volume.url.path == "/Volumes/PauloSSDExterno")
    }

    @Test func testConvenienceNameInitialization() {
        let volume = TargetVolume(name: "BackupDrive", bsdNode: "/dev/disk5")
        #expect(volume.name == "BackupDrive")
        #expect(volume.mountPoint == "/Volumes/BackupDrive")
        #expect(volume.bsdNode == "/dev/disk5")
        #expect(volume.url.path == "/Volumes/BackupDrive")
    }

    @Test func testCustomInitialization() {
        let volume = TargetVolume(name: "Scratch", mountPoint: "/Volumes/ScratchDisk", bsdNode: "/dev/disk12")
        #expect(volume.name == "Scratch")
        #expect(volume.mountPoint == "/Volumes/ScratchDisk")
        #expect(volume.bsdNode == "/dev/disk12")
        #expect(volume.url == URL(fileURLWithPath: "/Volumes/ScratchDisk"))
    }

    @Test func testValueEquality() {
        let vol1 = TargetVolume(name: "SSD1", mountPoint: "/Volumes/SSD1", bsdNode: "/dev/disk8")
        let vol2 = TargetVolume(name: "SSD1", mountPoint: "/Volumes/SSD1", bsdNode: "/dev/disk8")
        let vol3 = TargetVolume(name: "SSD1", mountPoint: "/Volumes/SSD1", bsdNode: "/dev/disk9")

        #expect(vol1 == vol2)
        #expect(vol1 != vol3)
    }

    @Test func testUpdatingBSDNode() {
        let original = TargetVolume(name: "ExternalSSD", mountPoint: "/Volumes/ExternalSSD", bsdNode: "/dev/disk8")
        let updated = original.updatingBSDNode("/dev/disk10")

        #expect(original.bsdNode == "/dev/disk8")
        #expect(updated.name == "ExternalSSD")
        #expect(updated.mountPoint == "/Volumes/ExternalSSD")
        #expect(updated.bsdNode == "/dev/disk10")
    }

    @Test func testIsMountedValidation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MountedVol_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mountedVol = TargetVolume(name: "Temp", mountPoint: tempDir.path, bsdNode: "/dev/disk8")
        #expect(mountedVol.isMounted == true)

        let unmountedVol = TargetVolume(name: "Temp", mountPoint: "/Volumes/NonExistent_\(UUID().uuidString)", bsdNode: "/dev/disk8")
        #expect(unmountedVol.isMounted == false)
    }
}
