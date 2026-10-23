import Foundation
import Testing

@testable import MochiCore

/// WebKit on macOS has no public pointer-lock API: it asks the `uiDelegate` through the private
/// selector below, and when the delegate doesn't answer it, every `requestPointerLock()` is
/// refused — a browser game's camera never follows the mouse. The selector is looked up by name,
/// so a misspelt `@objc(...)` compiles and fails just as silently.
@Suite struct PointerLockDelegateTests {
    @Test func widgetHandleAnswersWebKitsPointerLockSelector() {
        let selector = NSSelectorFromString("_webViewDidRequestPointerLock:completionHandler:")
        #expect(AppKitWidgetWindowHandle.instancesRespond(to: selector))
    }
}
