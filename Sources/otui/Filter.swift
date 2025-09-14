import Foundation

func filterLines(_ lines: [String], query: String?) -> [String] {
    guard let q = query, !q.isEmpty else { return lines }
    return lines.filter { $0.range(of: q, options: .caseInsensitive) != nil }
}
