import Foundation

/// Subsequence matching with fzf-style scoring: every query character must
/// appear in order, and matches score higher when they are consecutive or fall
/// at the start of a path segment.
enum FuzzyMatcher {
    static func score(_ candidate: String, query: String) -> Int? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }

        let haystack = Array(candidate.lowercased())
        var total = 0
        var needleIndex = 0
        var previousMatch = -1

        for (index, character) in haystack.enumerated() {
            guard needleIndex < needle.count, character == needle[needleIndex] else {
                continue
            }

            var points = 1
            if previousMatch == index - 1 {
                points += 4
            }
            // Start of a path segment is the most meaningful position.
            if index == 0 || haystack[index - 1] == "/" {
                points += 6
            }
            total += points
            previousMatch = index
            needleIndex += 1
        }

        guard needleIndex == needle.count else { return nil }

        // Prefer shorter candidates when scores are otherwise equal.
        return total * 100 - haystack.count
    }

    /// Candidates that match, best first.
    static func rank(_ candidates: [String], query: String) -> [String] {
        candidates
            .compactMap { candidate -> (String, Int)? in
                guard let score = score(candidate, query: query) else { return nil }
                return (candidate, score)
            }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
            }
            .map(\.0)
    }
}
