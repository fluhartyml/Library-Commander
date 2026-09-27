//
//  ServerManager.swift
//  Library Commander
//
//  Created by Michael Fluharty with Claude on 2025 Nov 11 1056
//

import Foundation
import SwiftUI

@Observable
class ServerManager {
    var servers: [ServerConfig] = []

    private let fileManager = FileManager.default
    private var configFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Library Commander", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: appFolder.path) {
            try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent("servers.json")
    }

    init() {
        loadServers()
    }

    // MARK: - Persistence

    func loadServers() {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            servers = []
            return
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            servers = try JSONDecoder().decode([ServerConfig].self, from: data)
        } catch {
            print("Error loading servers: \(error)")
            servers = []
        }
    }

    func saveServers() {
        print("💾 [ServerManager] saveServers() to: \(configFileURL.path)")
        do {
            let data = try JSONEncoder().encode(servers)
            print("💾 [ServerManager] Encoded \(data.count) bytes")
            try data.write(to: configFileURL, options: .atomic)
            print("💾 [ServerManager] ✅ Save successful")
        } catch {
            print("❌ [ServerManager] Error saving servers: \(error)")
        }
    }

    // MARK: - CRUD Operations

    func addServer(_ server: ServerConfig) {
        print("📝 [ServerManager] addServer() called: \(server.name)")
        servers.append(server)
        print("📝 [ServerManager] Servers array count: \(servers.count)")
        saveServers()
        print("📝 [ServerManager] saveServers() completed")
    }

    func updateServer(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            saveServers()
        }
    }

    func deleteServer(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        saveServers()
    }

    func deleteServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }
}
