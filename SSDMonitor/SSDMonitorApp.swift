//
//  SSDMonitorApp.swift
//  SSDMonitor
//
//  App de Menu Bar para monitoramento de SSD Externo (PauloSSDExterno)
//

import SwiftUI
import AppKit

@main
struct SSDMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    let watcher = DiskWatcher()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NotificationManager.shared.requestAuthorization()
        AutoStartManager.shared.updateStatus()
        statusBarController = StatusBarController(watcher: watcher)
    }
}
