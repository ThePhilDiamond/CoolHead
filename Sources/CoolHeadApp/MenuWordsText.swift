import CoolHeadCore
import SwiftUI

extension Text {
    /// Text with the menu items, buttons, headings and addresses `Fmt.ui` marked drawn underlined (see MenuWords.swift).
    init(ui s: String) {
        var out = AttributedString()
        for run in Fmt.uiRuns(s) {
            var part = AttributedString(run.text)
            if run.underlined { part.underlineStyle = .single }
            out += part
        }
        self.init(out)
    }
}
