/// A synchronous, bounded recognition path shared with Color Tools. No I/O or permissions.
nonisolated struct ColorSearchProvider: Sendable {
    func color(for query: String) -> CommandlyColor? {
        CommandlyColorParser.parse(query)
    }
}
