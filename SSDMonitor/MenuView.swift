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
    @StateObject private var autoStart = AutoStartManager.shared
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
                .foregroundColor(watcher.isMounted ? .accentColor : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                if !watcher.availableVolumes.isEmpty {
                    Menu {
                        ForEach(watcher.availableVolumes, id: \.mountPoint) { vol in
                            Button(action: {
                                watcher.selectVolume(vol)
                            }) {
                                HStack {
                                    Text(vol.name)
                                    if vol.name == watcher.targetVolumeName {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(watcher.targetVolumeName)
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    Text(watcher.targetVolumeName)
                        .font(.headline)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if watcher.isMounted {
                        Text(watcher.bsdIdentifier)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                        
                        Label("Montado", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label("Desconectado", systemImage: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                watcher.refreshAll()
            }) {
                if watcher.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(watcher.isRefreshing)
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
                                .foregroundColor(thermalColor(watcher.thermalStatus))
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
                    
                    if watcher.temperature != nil {
                        let status = watcher.thermalStatus
                        StatusBadge(
                            title: status.level.shortBadgeTitle,
                            icon: thermalBadgeIcon(status),
                            color: thermalColor(status)
                        )
                    }
                }
            }
            
            if watcher.isThrottling {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Thermal Throttling Detectado")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            Spacer()
                            Text("Gatilho: ≥ 70°C")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                        Text(watcher.thermalStatus.subtitleText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            
            if let sensors = watcher.temperatureSensors, sensors.count >= 2 {
                Divider()
                    .padding(.vertical, 2)
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption2)
                            .foregroundColor(sensors[0] >= 70 ? .red : .secondary)
                        Text("Controladora: \(sensors[0])°C")
                            .font(.caption2)
                            .fontWeight(sensors[0] >= 70 ? .bold : .medium)
                            .foregroundColor(sensors[0] >= 70 ? .red : .secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                            .font(.caption2)
                            .foregroundColor(sensors[1] >= 70 ? .red : .secondary)
                        Text("NAND Flash: \(sensors[1])°C")
                            .font(.caption2)
                            .fontWeight(sensors[1] >= 70 ? .bold : .medium)
                            .foregroundColor(sensors[1] >= 70 ? .red : .secondary)
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
            
            if watcher.isMounted {
                TemperatureGraphView(
                    history: watcher.temperatureHistory,
                    currentSensors: watcher.temperatureSensors
                )
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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 76, height: 76)
                
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.orange)
            }
            .padding(.top, 6)
            
            VStack(spacing: 4) {
                Text("SSD Desconectado")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Aguardando conexão de \"\(watcher.targetVolumeName)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("O SSDMonitor detectará automaticamente o disco assim que ele for conectado ao Mac em \(watcher.targetMountPoint).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .padding(.horizontal, 4)
            
            if !watcher.availableVolumes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Outros SSDs Externos Conectados:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(watcher.availableVolumes, id: \.mountPoint) { vol in
                        Button(action: {
                            watcher.selectVolume(vol)
                        }) {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundColor(.accentColor)
                                Text(vol.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("Monitorar Este")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(8)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            Button(action: {
                watcher.refreshAll()
            }) {
                HStack(spacing: 6) {
                    if watcher.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Verificar Conexão Agora")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .disabled(watcher.isRefreshing)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
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
            
            HStack(spacing: 8) {
                if watcher.isMounted {
                    Button(action: {
                        watcher.ejectVolume(force: false)
                    }) {
                        HStack(spacing: 4) {
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
                    .disabled(watcher.isEjecting)
                    
                    if watcher.errorMessage != nil {
                        Button(action: {
                            watcher.ejectVolume(force: true)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Forçar Ejeção")
                                    .fontWeight(.medium)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(watcher.isEjecting)
                        .help("Força o desmonte do volume ignorando arquivos travados pelo sistema")
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 2)
            
            HStack {
                Toggle("Iniciar com o Mac", isOn: Binding(
                    get: { autoStart.isAutoStartEnabled },
                    set: { autoStart.toggleAutoStart($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption2)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Encerrar")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(4)
                }
                .buttonStyle(.plain)
                .help("Sair do SSDMonitor")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func thermalColor(_ status: ThermalStatus) -> Color {
        switch status.level {
        case .normal:
            return .green
        case .warm:
            return .orange
        case .throttling:
            return .orange
        case .critical:
            return .red
        }
    }
    
    private func thermalBadgeIcon(_ status: ThermalStatus) -> String {
        switch status.level {
        case .normal:
            return "thermometer.medium"
        case .warm:
            return "thermometer.sun.fill"
        case .throttling:
            return "flame.fill"
        case .critical:
            return "exclamationmark.triangle.fill"
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

struct TemperatureGraphView: View {
    let history: [TemperatureReading]
    let currentSensors: [Int]?

    private var minTemp: Int {
        history.map(\.temperature).min() ?? 0
    }

    private var maxTemp: Int {
        history.map(\.temperature).max() ?? 0
    }

    private var avgTemp: Int {
        guard !history.isEmpty else { return 0 }
        let total = history.map(\.temperature).reduce(0, +)
        return Int(round(Double(total) / Double(history.count)))
    }

    private var graphColor: Color {
        if maxTemp >= 75 {
            return .red
        } else if maxTemp >= 70 {
            return .orange
        } else if maxTemp >= 55 {
            return .orange
        } else {
            return .green
        }
    }

    private func yPos(for temp: Double, in height: CGFloat, yMin: Double, yRange: Double) -> CGFloat {
        let normalized = (temp - yMin) / yRange
        return height * CGFloat(1.0 - normalized)
    }

    private func xPos(for index: Int, total: Int, in width: CGFloat) -> CGFloat {
        guard total > 1 else { return width / 2 }
        return width * (CGFloat(index) / CGFloat(total - 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Histórico Térmico", systemImage: "waveform.path.ecg")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if !history.isEmpty {
                    HStack(spacing: 8) {
                        metricText(label: "Mín", value: "\(minTemp)°C", color: .green)
                        metricText(label: "Méd", value: "\(avgTemp)°C", color: .blue)
                        metricText(label: "Máx", value: "\(maxTemp)°C", color: maxTemp >= 70 ? .red : .orange)
                    }
                }
            }

            if history.count >= 2 {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height

                    let yMin = Double(min(minTemp - 3, 30))
                    let yMax = Double(max(maxTemp + 5, 80))
                    let yRange = max(1.0, yMax - yMin)
                    let y70 = yPos(for: 70, in: height, yMin: yMin, yRange: yRange)
                    let y55 = yPos(for: 55, in: height, yMin: yMin, yRange: yRange)

                    ZStack(alignment: .topLeading) {
                        if y70 >= 0 && y70 <= height {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y70))
                                path.addLine(to: CGPoint(x: width, y: y70))
                            }
                            .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                            Text("70°C Throttling")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(3)
                                .position(x: width - 36, y: max(8, y70 - 7))
                        }

                        if y55 >= 0 && y55 <= height && abs(y55 - y70) > 14 {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y55))
                                path.addLine(to: CGPoint(x: width, y: y55))
                            }
                            .stroke(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }

                        Path { path in
                            path.move(to: CGPoint(x: 0, y: height))
                            for (idx, item) in history.enumerated() {
                                let x = xPos(for: idx, total: history.count, in: width)
                                let y = yPos(for: Double(item.temperature), in: height, yMin: yMin, yRange: yRange)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            path.addLine(to: CGPoint(x: width, y: height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [graphColor.opacity(0.22), graphColor.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        Path { path in
                            for (idx, item) in history.enumerated() {
                                let x = xPos(for: idx, total: history.count, in: width)
                                let y = yPos(for: Double(item.temperature), in: height, yMin: yMin, yRange: yRange)
                                let pt = CGPoint(x: x, y: y)
                                if idx == 0 {
                                    path.move(to: pt)
                                } else {
                                    path.addLine(to: pt)
                                }
                            }
                        }
                        .stroke(graphColor, lineWidth: 2)

                        if let lastIdx = history.indices.last {
                            let x = xPos(for: lastIdx, total: history.count, in: width)
                            let y = yPos(for: Double(history[lastIdx].temperature), in: height, yMin: yMin, yRange: yRange)
                            let pt = CGPoint(x: x, y: y)

                            Circle()
                                .fill(graphColor)
                                .frame(width: 6, height: 6)
                                .position(pt)
                        }
                    }
                }
                .frame(height: 60)
            } else {
                HStack {
                    Spacer()
                    Text("Coletando histórico de temperatura...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                    Spacer()
                }
                .frame(height: 40)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func metricText(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(label):")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
        }
    }
}
