//
//  TargetVolume.swift
//  SSDMonitor
//
//  Objeto de valor imutável que representa um volume de disco alvo para monitoramento.
//

import Foundation

/// Objeto de valor imutável que encapsula nome do volume, ponto de montagem e nó de dispositivo BSD.
public struct TargetVolume: Hashable, Equatable, Sendable, CustomStringConvertible {
    /// Nome amigável do volume (ex: "PauloSSDExterno").
    public let name: String
    
    /// Caminho do ponto de montagem no sistema de arquivos (ex: "/Volumes/PauloSSDExterno").
    public let mountPoint: String
    
    /// Identificador do nó de dispositivo BSD no macOS (ex: "/dev/disk8").
    public let bsdNode: String
    
    /// Inicializador principal.
    public init(name: String = "PauloSSDExterno", mountPoint: String = "/Volumes/PauloSSDExterno", bsdNode: String = "/dev/disk8") {
        self.name = name
        self.mountPoint = mountPoint
        self.bsdNode = bsdNode
    }
    
    /// Inicializador conveniente a partir de um nome de volume e nó BSD opcional.
    public init(name: String, bsdNode: String = "/dev/disk8") {
        self.name = name
        self.mountPoint = "/Volumes/\(name)"
        self.bsdNode = bsdNode
    }
    
    /// URL do ponto de montagem no sistema de arquivos.
    public var url: URL {
        URL(fileURLWithPath: mountPoint)
    }
    
    /// Retorna `true` se o ponto de montagem existe no sistema de arquivos local.
    public var isMounted: Bool {
        FileManager.default.fileExists(atPath: mountPoint)
    }
    
    /// Lista todos os volumes externos de usuário montados em `/Volumes`.
    public static func listMountedExternalVolumes() -> [TargetVolume] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        
        let systemNames: Set<String> = ["Macintosh HD", "Macintosh HD - Data", "Preboot", "Recovery", "VM"]
        
        var result: [TargetVolume] = []
        for item in items {
            if item.hasPrefix(".") || systemNames.contains(item) { continue }
            let mountPath = "/Volumes/\(item)"
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: mountPath, isDirectory: &isDir), isDir.boolValue {
                if let resolved = try? fm.destinationOfSymbolicLink(atPath: mountPath), resolved == "/" {
                    continue
                }
                result.append(TargetVolume(name: item, mountPoint: mountPath))
            }
        }
        return result
    }
    
    /// Cria uma nova instância de `TargetVolume` com um nó de dispositivo BSD atualizado.
    public func updatingBSDNode(_ newBSDNode: String) -> TargetVolume {
        TargetVolume(name: self.name, mountPoint: self.mountPoint, bsdNode: newBSDNode)
    }
    
    public var description: String {
        "TargetVolume(name: '\(name)', mountPoint: '\(mountPoint)', bsdNode: '\(bsdNode)')"
    }
}
