import Foundation
import Testing

@testable import MochiCore

/// #105: which download failures mean the system refused the write — the only sign Mochi ever
/// gets that the Downloads folder's 文件和文件夹 permission is off.
@Suite struct DownloadWriteResultTests {
    @Test func noErrorIsASuccess() {
        #expect(DownloadWriteResult.classifying(nil) == .succeeded)
    }

    @Test(arguments: [
        (error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue), expected: DownloadWriteResult.deniedPermission),
        (error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue), expected: .deniedPermission),
        (error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)), expected: .deniedPermission),
        (error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), expected: .deniedPermission),
        // WebKit reports a destination it couldn't create or open as a URL error; with nothing
        // underneath to say otherwise, refusal is what that means for an existing folder.
        (error: NSError(domain: NSURLErrorDomain, code: URLError.cannotCreateFile.rawValue), expected: .deniedPermission),
        (error: NSError(domain: NSURLErrorDomain, code: URLError.cannotOpenFile.rawValue), expected: .deniedPermission),
        // …but when there is something underneath, it decides.
        (error: NSError(
            domain: NSURLErrorDomain, code: URLError.cannotCreateFile.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))]),
         expected: .failed),
        (error: NSError(
            domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))]),
         expected: .deniedPermission),
        (error: NSError(
            domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))]),
         expected: .deniedPermission),
        // Everything else is some other failure: the network, a full disk, a cancel.
        (error: NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue), expected: .failed),
        (error: NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue), expected: .failed),
        (error: NSError(domain: NSURLErrorDomain, code: URLError.cannotWriteToFile.rawValue), expected: .failed),
        (error: NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue), expected: .failed),
        (error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), expected: .failed),
        (error: NSError(domain: "WebKitErrorDomain", code: 1), expected: .failed),
    ])
    func classifies(_ row: (error: NSError, expected: DownloadWriteResult)) {
        #expect(DownloadWriteResult.classifying(row.error) == row.expected)
    }
}
