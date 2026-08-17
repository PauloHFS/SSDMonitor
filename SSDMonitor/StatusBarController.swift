//
//  StatusBarController.swift
//  SSDMonitor
//
//  Controlador nativo de NSStatusItem e NSPopover para a Barra de Menus do macOS.
//

import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var watcher: DiskWatcher
    private var cancellables = Set<AnyCancellable>()

    public init(watcher: DiskWatcher) {
        self.watcher = watcher
        
        // 1. Criar StatusItem nativo do AppKit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 2. Criar Popover nativo do AppKit com NSHostingController
        let hostingController = NSHostingController(rootView: MenuView(watcher: watcher))
        hostingController.preferredContentSize = NSSize(width: 360, height: 480)
        
        self.popover = NSPopover()
        self.popover.contentSize = NSSize(width: 360, height: 480)
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.contentViewController = hostingController
        
        super.init()
        
        // 3. Configurar botão da Barra de Menus
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
        }
        
        // 4. Observar atualizações do DiskWatcher para atualizar o título e ícone na barra de menus
        Publishers.Merge(
            watcher.$temperature.map { _ in () },
            watcher.$isMounted.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.updateStatusButton(temperature: self.watcher.temperature, isMounted: self.watcher.isMounted)
        }
        .store(in: &cancellables)

        // 5. Manter o popover aberto durante a ejeção e fechar automaticamente apenas em caso de sucesso
        watcher.$isEjecting
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEjecting in
                guard let self = self else { return }
                if isEjecting {
                    self.popover.behavior = .semitransient
                } else {
                    self.popover.behavior = .transient
                }
            }
            .store(in: &cancellables)

        // 6. Visibilidade dinâmica do statusItem e Notificações de montagem/desmonte
        watcher.$isMounted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMounted in
                guard let self = self else { return }
                self.statusItem.isVisible = isMounted
                if !isMounted && self.popover.isShown && self.watcher.errorMessage == nil {
                    self.popover.performClose(nil)
                }
            }
            .store(in: &cancellables)

        watcher.$isMounted
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMounted in
                guard let self = self else { return }
                if isMounted {
                    NotificationManager.shared.sendNotification(
                        title: "SSD Conectado",
                        body: "O SSD '\(self.watcher.targetVolumeName)' foi reconhecido. Telemetria e monitoramento ativos."
                    )
                } else {
                    NotificationManager.shared.sendNotification(
                        title: "SSD Desconectado / Ejetado",
                        body: "O SSD '\(self.watcher.targetVolumeName)' foi ejetado com segurança."
                    )
                }
            }
            .store(in: &cancellables)

        // Visibilidade inicial baseada na presença do disco
        statusItem.isVisible = watcher.isMounted
        if !watcher.isMounted {
            NotificationManager.shared.sendNotification(
                title: "SSDMonitor em Segundo Plano",
                body: "Aguardando conexão de '\(watcher.targetVolumeName)'. O ícone surgirá na barra de menus ao conectar."
            )
        }
        
        updateStatusButton(temperature: watcher.temperature, isMounted: watcher.isMounted)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        logWatcher("Botão da Barra de Menus clicado! Popover isShown: \(popover.isShown)")
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusButton(temperature: Int?, isMounted: Bool) {
        guard let button = statusItem.button else { return }
        
        let iconName = isMounted ? "externaldrive.fill" : "externaldrive.badge.xmark"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SSD")
        button.imagePosition = .imageLeft
        
        if isMounted, let temp = temperature {
            button.title = " \(temp)°C"
        } else if isMounted {
            button.title = " PauloSSD"
        } else {
            button.title = " SSD Off"
        }
        logWatcher("StatusItem atualizado na barra de menus: '\(button.title)'")
    }
}
