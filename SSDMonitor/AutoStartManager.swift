//
//  AutoStartManager.swift
//  SSDMonitor
//
//  Gerenciador de Inicialização no Login do macOS via SMAppService
//

import Foundation
import ServiceManagement
import Combine

@MainActor
public final class AutoStartManager: ObservableObject {
    public static let shared = AutoStartManager()
    
    @Published public var isAutoStartEnabled: Bool = false
    
    private init() {
        updateStatus()
    }
    
    public func updateStatus() {
        if #available(macOS 13.0, *) {
            isAutoStartEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    public func toggleAutoStart(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    logWatcher("AutoStart no Login habilitado com sucesso.")
                } else {
                    try SMAppService.mainApp.unregister()
                    logWatcher("AutoStart no Login desabilitado com sucesso.")
                }
                updateStatus()
            } catch {
                logWatcher("Erro ao alterar AutoStart no Login: \(error.localizedDescription)")
                updateStatus()
            }
        }
    }
}
