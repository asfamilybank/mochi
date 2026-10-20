import Foundation

/// A page's address as the user reads it (#141): what `URL.absoluteString` carries as percent
/// escapes is shown as the characters they stand for, the way Safari shows it. For showing only —
/// opening, copying and storing an address still use the `URL` itself.
///
/// Only escapes of non-ASCII bytes are decoded. An ASCII escape is there because the character
/// would mean something else unescaped (`%2F`, `%3F`, `%26`) or would not be seen (`%20`), so it
/// stays as it is.
public enum URLDisplay {
    public static func text(of url: URL) -> String {
        let bytes = Array(url.absoluteString.utf8)
        var shown: [UInt8] = []
        var index = 0
        while index < bytes.count {
            var run: [UInt8] = []
            var end = index
            while let byte = escapedByte(in: bytes, at: end), byte >= 0x80 {
                run.append(byte)
                end += 3
            }
            if run.isEmpty {
                shown.append(bytes[index])
                index += 1
            } else {
                shown += decoded(run, escapes: bytes[index..<end])
                index = end
            }
        }
        return String(decoding: shown, as: UTF8.self)
    }

    /// `text` the way an address carries it (#143): each character `text(of:)` would show decoded,
    /// as the percent escapes it stands for — so what is typed can be looked for in an address
    /// that is stored encoded. What `text(of:)` leaves escaped stays as typed: an address showing
    /// it escaped is matched by its escapes.
    static func escaped(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            if scalar.isASCII || !isVisible(scalar) {
                escaped.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { escaped += String(format: "%%%02X", byte) }
            }
        }
        return escaped
    }

    /// `run`, the bytes behind a row of escapes, one character at a time: a byte that does not
    /// start a whole UTF-8 character keeps its escape, and so does a character `isVisible` turns away.
    private static func decoded(_ run: [UInt8], escapes: ArraySlice<UInt8>) -> [UInt8] {
        var shown: [UInt8] = []
        var index = 0
        while index < run.count {
            let length = utf8Length(leadingWith: run[index])
            if index + length <= run.count, let character = String(validating: run[index..<index + length], as: UTF8.self),
                character.unicodeScalars.allSatisfy(isVisible)
            {
                shown += run[index..<index + length]
                index += length
            } else {
                let escape = escapes.startIndex + 3 * index
                shown += escapes[escape..<escape + 3]
                index += 1
            }
        }
        return shown
    }

    /// Whether `scalar` shows as itself. Spaces, controls and format characters (zero-width ones,
    /// direction overrides) would make the address read as something it is not, so their escapes stay.
    private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate,
            .unassigned:
            false
        default:
            true
        }
    }

    /// How many bytes the UTF-8 character starting with `byte` takes; 1 for a byte that starts
    /// none, which then fails validation on its own.
    private static func utf8Length(leadingWith byte: UInt8) -> Int {
        switch byte {
        case 0xC0...0xDF: 2
        case 0xE0...0xEF: 3
        case 0xF0...0xF7: 4
        default: 1
        }
    }

    /// The byte `%XX` at `index` stands for, if there is one.
    private static func escapedByte(in bytes: [UInt8], at index: Int) -> UInt8? {
        guard index + 2 < bytes.count, bytes[index] == UInt8(ascii: "%") else { return nil }
        return UInt8(String(decoding: bytes[index + 1...index + 2], as: UTF8.self), radix: 16)
    }
}
