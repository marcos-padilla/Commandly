import Foundation

enum MarkdownDiagramRenderer {
    static func render(language: String, source: String) -> String? {
        switch language.lowercased() {
        case "mermaid":
            return renderDirectedGraph(source: source, syntax: .mermaid)
        case "dot", "graphviz":
            return renderDirectedGraph(source: source, syntax: .graphviz)
        case "vega", "vega-lite", "vegalite":
            return renderVegaBars(source: source)
        default:
            return nil
        }
    }

    private enum GraphSyntax {
        case mermaid
        case graphviz
    }

    private struct Edge: Equatable {
        let from: String
        let to: String
    }

    private static func renderDirectedGraph(source: String, syntax: GraphSyntax) -> String? {
        let arrowPattern = syntax == .mermaid
            ? #"([A-Za-z][A-Za-z0-9_-]*)[^\n;]*?(?:-->|==>|---)[^\n;]*?([A-Za-z][A-Za-z0-9_-]*)"#
            : #"([A-Za-z][A-Za-z0-9_-]*)\s*->\s*([A-Za-z][A-Za-z0-9_-]*)"#
        guard let expression = try? NSRegularExpression(pattern: arrowPattern) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        let matches = expression.matches(in: source, range: range).prefix(24)
        var edges: [Edge] = []
        for match in matches {
            guard let fromRange = Range(match.range(at: 1), in: source),
                  let toRange = Range(match.range(at: 2), in: source) else { continue }
            let edge = Edge(from: String(source[fromRange]), to: String(source[toRange]))
            if edge.from != edge.to, !edges.contains(edge) { edges.append(edge) }
        }
        guard !edges.isEmpty else { return nil }

        var labels: [String: String] = [:]
        if let labelExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9_-]*)\s*[\[\(\{]\s*([^\]\)\}\n]+)\s*[\]\)\}]"#
        ) {
            for match in labelExpression.matches(in: source, range: range).prefix(48) {
                guard let idRange = Range(match.range(at: 1), in: source),
                      let labelRange = Range(match.range(at: 2), in: source) else { continue }
                labels[String(source[idRange])] = String(source[labelRange])
            }
        }

        var nodes: [String] = []
        for edge in edges {
            if !nodes.contains(edge.from) { nodes.append(edge.from) }
            if !nodes.contains(edge.to) { nodes.append(edge.to) }
        }
        nodes = Array(nodes.prefix(20))
        let permitted = Set(nodes)
        edges = edges.filter { permitted.contains($0.from) && permitted.contains($0.to) }

        let width = 680.0
        let rowHeight = 92.0
        let height = max(160, Double(nodes.count) * rowHeight + 36)
        var positions: [String: (x: Double, y: Double)] = [:]
        for (index, node) in nodes.enumerated() {
            let column = index % 2
            let row = index / 2
            positions[node] = (
                x: column == 0 ? 190 : 490,
                y: 58 + Double(row) * rowHeight
            )
        }

        var shapes = ""
        for edge in edges {
            guard let start = positions[edge.from], let end = positions[edge.to] else { continue }
            shapes += "<line x1=\"\(start.x)\" y1=\"\(start.y + 24)\" x2=\"\(end.x)\" y2=\"\(end.y - 24)\" class=\"diagram-edge\" marker-end=\"url(#arrow)\"/>"
        }
        for node in nodes {
            guard let position = positions[node] else { continue }
            let label = labels[node] ?? node
            let boundedLabel = String(label.prefix(54))
            shapes += "<rect x=\"\(position.x - 112)\" y=\"\(position.y - 24)\" width=\"224\" height=\"48\" rx=\"10\" class=\"diagram-node\"/>"
            shapes += "<text x=\"\(position.x)\" y=\"\(position.y + 5)\" text-anchor=\"middle\" class=\"diagram-label\">\(MarkdownHTML.escapeText(boundedLabel))</text>"
        }

        return """
        <figure class="diagram safe-diagram" data-diagram-kind="\(syntax == .mermaid ? "mermaid" : "graphviz")">
        <svg role="img" aria-label="Diagram preview" viewBox="0 0 \(width) \(height)" xmlns="http://www.w3.org/2000/svg">
        <defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" class="diagram-arrow"/></marker></defs>
        \(shapes)
        </svg>
        </figure>
        """
    }

    private static func renderVegaBars(source: String) -> String? {
        guard let data = source.data(using: .utf8),
              data.count <= 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObject = root["data"] as? [String: Any],
              let values = dataObject["values"] as? [[String: Any]],
              !values.isEmpty,
              let encoding = root["encoding"] as? [String: Any],
              let xField = (encoding["x"] as? [String: Any])?["field"] as? String,
              let yField = (encoding["y"] as? [String: Any])?["field"] as? String else {
            return nil
        }

        let points: [(label: String, value: Double)] = values.prefix(16).compactMap { row in
            guard let number = row[yField] as? NSNumber,
                  !(number is Bool) else { return nil }
            return (String(describing: row[xField] ?? ""), number.doubleValue)
        }
        guard !points.isEmpty else { return nil }
        let maximum = points.map(\.value).max() ?? 0
        let minimum = min(0, points.map(\.value).min() ?? 0)
        guard maximum > minimum else { return nil }

        let width = 680.0
        let height = 360.0
        let plotHeight = 270.0
        let baseY = 310.0 - ((0 - minimum) / (maximum - minimum) * plotHeight)
        let step = 590.0 / Double(points.count)
        var shapes = "<line x1=\"54\" y1=\"\(baseY)\" x2=\"650\" y2=\"\(baseY)\" class=\"chart-axis\"/>"
        for (index, point) in points.enumerated() {
            let scaledY = 310.0 - ((point.value - minimum) / (maximum - minimum) * plotHeight)
            let x = 62.0 + Double(index) * step
            let barWidth = max(5, step * 0.68)
            let y = min(scaledY, baseY)
            let barHeight = max(1, abs(baseY - scaledY))
            let label = MarkdownHTML.escapeText(String(point.label.prefix(14)))
            shapes += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(barWidth)\" height=\"\(barHeight)\" rx=\"3\" class=\"chart-bar\"><title>\(label): \(point.value)</title></rect>"
            shapes += "<text x=\"\(x + barWidth / 2)\" y=\"336\" text-anchor=\"middle\" class=\"chart-label\">\(label)</text>"
        }
        return """
        <figure class="diagram safe-diagram" data-diagram-kind="vega">
        <svg role="img" aria-label="Chart preview" viewBox="0 0 \(width) \(height)" xmlns="http://www.w3.org/2000/svg">\(shapes)</svg>
        </figure>
        """
    }
}
