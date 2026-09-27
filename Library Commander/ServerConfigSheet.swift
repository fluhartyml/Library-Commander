//
//  ServerConfigSheet.swift
//  Library Commander
//
//  Created by Michael Fluharty with Claude on 2025 Nov 11 1056
//

import SwiftUI

struct ServerConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    let serverManager: ServerManager
    let onSave: (ServerConfig, String) -> Void

    @State private var name: String = "Home Server"
    @State private var address: String = ""
    @State private var shareName: String = "Documents"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var serverType: ServerType = .smb
    @State private var useCustomPort: Bool = false
    @State private var customPort: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Server")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Server Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Details")
                            .font(.system(size: 18, weight: .semibold))

                        TextField("Name", text: $name, prompt: Text("Home NAS"))
                            .textFieldStyle(.roundedBorder)

                        Picker("Type", selection: $serverType) {
                            ForEach(ServerType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Connection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection")
                            .font(.system(size: 18, weight: .semibold))

                        TextField("Address", text: $address, prompt: Text("192.168.1.100 or server.local"))
                            .textFieldStyle(.roundedBorder)

                        TextField("Share Name", text: $shareName, prompt: Text("Documents"))
                            .textFieldStyle(.roundedBorder)

                        Toggle("Use Custom Port", isOn: $useCustomPort)

                        if useCustomPort {
                            TextField("Port", text: $customPort, prompt: Text("445"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Credentials
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Credentials")
                            .font(.system(size: 18, weight: .semibold))

                        TextField("Username", text: $username, prompt: Text("admin"))
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password, prompt: Text("Required"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Add Server") {
                    saveServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
        }
        .frame(width: 500, height: 550)
    }

    private var isValid: Bool {
        let valid = !name.isEmpty &&
        !address.isEmpty &&
        !shareName.isEmpty &&
        !username.isEmpty &&
        !password.isEmpty &&
        (!useCustomPort || !customPort.isEmpty)

        // Debug validation state
        print("🔍 [Validation] isValid: \(valid)")
        print("🔍 [Validation] name: '\(name)' isEmpty: \(name.isEmpty)")
        print("🔍 [Validation] address: '\(address)' isEmpty: \(address.isEmpty)")
        print("🔍 [Validation] shareName: '\(shareName)' isEmpty: \(shareName.isEmpty)")
        print("🔍 [Validation] username: '\(username)' isEmpty: \(username.isEmpty)")
        print("🔍 [Validation] password: <hidden> isEmpty: \(password.isEmpty)")
        print("🔍 [Validation] useCustomPort: \(useCustomPort)")
        if useCustomPort {
            print("🔍 [Validation] customPort: '\(customPort)' isEmpty: \(customPort.isEmpty)")
        }

        return valid
    }

    private func saveServer() {
        print("💾 [ServerConfig] saveServer() called")
        print("💾 [ServerConfig] Name: \(name)")
        print("💾 [ServerConfig] Address: \(address)")
        print("💾 [ServerConfig] Share: \(shareName)")
        print("💾 [ServerConfig] Username: \(username)")
        print("💾 [ServerConfig] Type: \(serverType)")
        print("💾 [ServerConfig] Custom Port: \(useCustomPort)")

        let port: Int? = useCustomPort ? Int(customPort) : nil

        let server = ServerConfig(
            name: name,
            address: address,
            shareName: shareName,
            username: username,
            serverType: serverType,
            port: port
        )

        print("💾 [ServerConfig] Calling onSave callback")
        onSave(server, password)
        print("💾 [ServerConfig] Calling dismiss()")
        dismiss()
    }
}
