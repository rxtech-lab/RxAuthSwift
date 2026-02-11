//
//  ContentView.swift
//  test
//
//  Created by Qiwei Li on 2/11/26.
//

import RxAuthSwift
import RxAuthSwiftUI
import SwiftUI

struct ContentView: View {
    @Bindable var manager: OAuthManager

    var body: some View {
        Group {
            switch manager.authState {
            case .unknown:
                ProgressView("Loading...")
                    .task {
                        await manager.checkExistingAuth()
                    }
            case .unauthenticated:
                RxSignInView(
                    manager: manager,
                    appearance: RxSignInAppearance(
                        title: "RxAuth Test",
                        subtitle: "Sign in to test authentication"
                    ),
                    onAuthSuccess: {
                        print("Auth succeeded")
                    },
                    onAuthFailed: { error in
                        print("Auth failed: \(error)")
                    }
                )
            case .authenticated:
                authenticatedView
            }
        }
    }

    private var authenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Welcome!")
                .accessibilityLabel("home-view-title")
                .font(.largeTitle)

            if let user = manager.currentUser {
                if let name = user.name {
                    Text(name)
                        .font(.title2)
                }
                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Sign Out") {
                Task {
                    await manager.logout()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
    }
}
