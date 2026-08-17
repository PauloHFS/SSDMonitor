//
//  MenuView.swift
//  SSDMonitor
//
//  Interface em cards SwiftUI para a barra de menu.
//

import SwiftUI

private let byteFormatter: ByteCountFormatter = {
    let bcf = ByteCountFormatter()
    bcf.allowedUnits = [.useGB, .useTB]
    bcf.countStyle = .file
    return bcf
}()

public struct MenuView: View {
    @ObservedObject var watcher: DiskWatcher
    @State private var expandedPID: pid_t? = nil
    
    public init(watcher: DiskWatcher) {
        self.watcher = watcher
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Header: Nome, Identificador Físico, Badge de Status e Atualizar
            headerSection
            
            Divider()
            
            if watcher.isMounted {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Card 1: Temperatura & SMART
                        temperatureCard
                        
                        // Card 2: Armazenamento
                        storageCard
                        
                        // Card 3: Processos Ativos (lsof)
                        activeProcessesCard
                    }
                }
                .frame(maxHeight: 420)
            } else {
                disconnectedView
            }
            
            Divider()
            
            // Footer: Ejetar Seguro e Ações
            footerSection
        }
        .padding(14)
        .frame(width: 360)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Image(systemName: watcher.isMounted ? "externaldrive.fill" : "externaldrive.badge.xmark")
                .font(.title2)
                .foregroundColor(watcher.isMounted ? .accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(watcher.targetVolumeName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(watcher.bsdIdentifier)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    
                    if watcher.isMounted {
                        Label("Montado", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label("Desconectado", systemImage: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                watcher.refreshAll()
            }) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(watcher.isRefreshing ? 360 : 0))
                    .animation(watcher.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: watcher.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Atualizar agora")
        }
    }
    
    // MARK: - Card 1: Temperatura & SMART
    
    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Temperatura & SMART", systemImage: "thermometer.medium")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                
                if let model = watcher.modelName {
                    Text(model)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    if let temp = watcher.temperature {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(temp)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(temperatureColor(temp))
                            Text("°C")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("-- °C")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let passed = watcher.smartPassed {
                        StatusBadge(
                            title: passed ? "SMART Saudável" : "SMART Alerta",
                            icon: passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                            color: passed ? .green : .red
                        )
                    } else {
                        StatusBadge(
                            title: "SMART N/A",
                            icon: "questionmark.shield",
                            color: .secondary
                        )
                    }
                    
                    if let temp = watcher.temperature {
                        Text(temperatureStatusText(temp))
                            .font(.caption2)
                            .foregroundColor(temperatureColor(temp))
                    }
                }
            }
            
            if let rawError = watcher.rawSmartError {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text(rawError)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(CardBackground())
    }
    
    // MARK: - Card 2: Armazenamento
    
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Armazenamento", systemImage: "internaldrive.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if let storage = watcher.storageInfo {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(storage.usedRatio > 0.9 ? Color.red : Color.accentColor)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(storage.usedRatio))), height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(byteFormatter.string(fromByteCount: storage.usedBytes)) usados")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(byteFormatter.string(fromByteCount: storage.freeBytes)) livres")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Total: \(byteFormatter.string(fromByteCount: storage.totalBytes))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%% usado", storage.usedRatio * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Informações de espaço indisponíveis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(CardBackground())
    }
    
    // MARK: - Card 3: Processos Ativos
    
    private var activeProcessesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Processos em Uso (\(watcher.activeProcesses.count))", systemImage: "cpu")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if watcher.activeProcesses.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Nenhum processo bloqueando o disco")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(watcher.activeProcesses) { proc in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proc.name)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Text("PID: \(proc.pid)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    watcher.killProcess(pid: proc.pid)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("Encerrar")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("Encerrar processo \(proc.pid)")
                            }
                            
                            if !proc.openFiles.isEmpty {
                                Button(action: {
                                    if expandedPID == proc.pid {
                                        expandedPID = nil
                                    } else {
                                        expandedPID = proc.pid
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: expandedPID == proc.pid ? "chevron.down" : "chevron.right")
                                        Text("\(proc.openFiles.count) arquivo(s) aberto(s)")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                
                                if expandedPID == proc.pid {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(proc.openFiles, id: \.self) { file in
                                            Text(file)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    .padding(6)
                                    .background(Color.black.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(12)
        .background(CardBackground())
    }
    
    // MARK: - Disconnected View
    
    private var disconnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            
            Text("Volume não montado")
                .font(.headline)
            
            Text("Conecte o SSD \"\(watcher.targetVolumeName)\" em \(watcher.targetMountPoint) para monitorar.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 8) {
            if let status = watcher.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(2)
            }
            
            if let error = watcher.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    watcher.ejectVolume()
                }) {
                    HStack {
                        if watcher.isEjecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "eject.fill")
                        }
                        Text("Ejetar Seguro")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!watcher.isMounted || watcher.isEjecting)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Sair do SSD Monitor")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func temperatureColor(_ temp: Int) -> Color {
        switch temp {
        case ..<55:
            return .green
        case 55..<68:
            return .orange
        default:
            return .red
        }
    }
    
    private func temperatureStatusText(_ temp: Int) -> String {
        switch temp {
        case ..<55:
            return "Temperatura Normal"
        case 55..<68:
            return "Temperatura Elevada"
        default:
            return "Temperatura Crítica!"
        }
    }
}

// MARK: - Subviews & Styles

struct StatusBadge: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}
