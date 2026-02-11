//
//  launch.swift
//  test
//
//  Created by Qiwei Li on 2/11/26.
//
import XCTest

func launchApp() -> XCUIApplication {
    let app = XCUIApplication()

    // --reset-auth flag will:
    // 1. Clear stored tokens from Keychain
    // 2. Use ephemeral Safari session (no cached credentials)
    app.launchArguments = ["--reset-auth"]

    app.launch()
    return app
}
