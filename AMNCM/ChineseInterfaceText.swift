import Foundation

enum ChineseInterfaceText {
    static func format(_ text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "「")
            .replacingOccurrences(of: "”", with: "」")
            .replacingOccurrences(of: #"‘([^’]+)’"#, with: "「$1」", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?<=\p{Han})(?=[A-Za-z0-9])|(?<=[A-Za-z0-9])(?=\p{Han})"#,
                with: " ",
                options: .regularExpression
            )
    }
}
