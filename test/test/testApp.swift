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
            redirectURI: "rxauth://callback",
            scopes: ["openid"],
            passkeyChallengePath: "/api/oauth/passkey/authenticate/options",
            passkeyVerificationPath: "/api/oauth/passkey/authenticate/verify",
            passkeyRegistrationChallengePath: "/api/oauth/passkey/register/options",
            passkeyRegistrationVerificationPath: "/api/oauth/passkey/register/verify",
            passkeyUpgradeChallengePath: "/api/oauth/passkey/upgrade/options",
            passkeyUpgradeVerificationPath: "/api/oauth/passkey/upgrade/verify",
            passkeyAccountCreationOptionsPath: "/api/oauth/passkey/account-creation/options",
            passkeyAccountCreationVerifyPath: "/api/oauth/passkey/account-creation/verify",
            passkeyRelyingPartyIdentifier: "rxlab.app"
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
