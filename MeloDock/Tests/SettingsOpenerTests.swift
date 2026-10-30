import AppKit
import XCTest
@testable import MeloDock

@MainActor
final class SettingsOpenerTests: XCTestCase {
    func testFindsCommandCommaItemRegardlessOfTitle() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "การตั้งค่า…", action: nil, keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q"))
        XCTAssertTrue(SettingsOpener.settingsItem(in: menu) === settings)
    }

    func testReturnsNilWithoutSettingsItem() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q"))
        XCTAssertNil(SettingsOpener.settingsItem(in: menu))
    }
}
