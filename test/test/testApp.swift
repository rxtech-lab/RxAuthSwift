//
//  testApp.swift
//  test
//
//  Created by Qiwei Li on 2/11/26.
//

import RxAuthSwift
import SwiftUI

@main
struct testApp: App {
    @State private var manager: OAuthManager

    init() {
        let configuration = RxAuthConfiguration(
            issuer: "https://auth.rxlab.app",
            clientID: "client_8605760939b8494c8bfe29c77ae7ee7f",
            redirectURI: "rxauth://callback"
        )

        let resetAuth = ProcessInfo.processInfo.arguments.contains("--reset-auth")
        let tokenStorage: TokenStorageProtocol? = resetAuth ? InMemoryTokenStorage() : nil

        if resetAuth {
            try? KeychainTokenStorage(serviceName: configuration.keychainServiceName).clearAll()
        }

        _manager = State(initialValue: OAuthManager(
            configuration: configuration,
            tokenStorage: tokenStorage
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
    }
}
