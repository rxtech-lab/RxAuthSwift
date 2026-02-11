//
//  testUITests.swift
//  testUITests
//
//  Created by Qiwei Li on 2/11/26.
//

import XCTest

final class testUITests: XCTestCase {
    @MainActor
    func testSignInWithoutIssue() throws {
        let app = launchApp()
        try app.signInWithEmailAndPassword()
    }
}
