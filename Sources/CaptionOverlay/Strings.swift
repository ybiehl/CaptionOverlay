import Foundation

/// Interface text in the user's language. The key is the English text;
/// German lives in Resources/de.lproj/Localizable.strings. Keys must be
/// single literals so the table lookup finds them.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
