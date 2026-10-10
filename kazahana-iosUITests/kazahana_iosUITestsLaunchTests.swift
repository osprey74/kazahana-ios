//
//  kazahana_iosUITestsLaunchTests.swift
//  kazahana-iosUITests
//
//  Created by 笹生総司 on 2026/03/18.
//

import XCTest

final class kazahana_iosUITestsLaunchTests: XCTestCase {

    // Xcode 27.0 では true にすると同一構成（ライト × 縦/横）を際限なく繰り返し、テストが終了しないため false にする
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
