import CoreGraphics

/// Pure geometry for tiling N panes into an auto-sized grid, like a tiling
/// window manager: as square a grid as the pane count allows, with the
/// focused pane's entire row and column enlarged so it reads as "the big
/// one" without breaking the 2D layout that arrow-key navigation relies on.
enum GridLayout {
    struct Result {
        /// Pane frames, indexed the same as the input pane list, in
        /// `bounds`'s coordinate space (AppKit: origin bottom-left).
        let frames: [CGRect]
        /// Pane index -> row (0 = top row).
        let rowOf: [Int]
        /// Pane index -> column within its row.
        let colOf: [Int]
        /// [row][col] -> pane index, top row first, row-major. A ragged
        /// last row simply has fewer entries.
        let indexAt: [[Int]]
    }

    enum Direction {
        case up, down, left, right
    }

    /// - Parameters:
    ///   - focusWeight: how many times wider/taller the focused pane's
    ///     column/row is versus a normal one.
    static func compute(
        count: Int,
        focusedIndex: Int,
        bounds: CGRect,
        spacing: CGFloat = 8,
        focusWeight: CGFloat = 1.7
    ) -> Result {
        guard count > 0 else {
            return Result(frames: [], rowOf: [], colOf: [], indexAt: [])
        }
        let focusedIndex = max(0, min(focusedIndex, count - 1))

        let cols = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(cols)))

        var rowOf = [Int](repeating: 0, count: count)
        var colOf = [Int](repeating: 0, count: count)
        var indexAt: [[Int]] = []
        for r in 0..<rows {
            let start = r * cols
            let end = min(start + cols, count)
            guard start < end else { break }
            var rowIndices: [Int] = []
            for (c, idx) in (start..<end).enumerated() {
                rowOf[idx] = r
                colOf[idx] = c
                rowIndices.append(idx)
            }
            indexAt.append(rowIndices)
        }

        let focusedRow = rowOf[focusedIndex]
        let focusedCol = colOf[focusedIndex]

        // Row heights come from global weights across every row.
        var rowWeights = [CGFloat](repeating: 1, count: indexAt.count)
        rowWeights[focusedRow] = focusWeight
        let totalRowWeight = rowWeights.reduce(0, +)
        let availableHeight = max(bounds.height - spacing * CGFloat(indexAt.count + 1), 0)
        let rowHeights = rowWeights.map { $0 / totalRowWeight * availableHeight }

        // Column widths are computed per row so a ragged last row still
        // fills the full width; the focused column only widens rows where
        // it's actually present.
        var frames = [CGRect](repeating: .zero, count: count)
        var y = bounds.maxY - spacing
        for (r, rowIndices) in indexAt.enumerated() {
            let rowHeight = rowHeights[r]
            let presentCols = rowIndices.count
            var colWeights = [CGFloat](repeating: 1, count: presentCols)
            if focusedCol < presentCols {
                colWeights[focusedCol] = focusWeight
            }
            let totalColWeight = colWeights.reduce(0, +)
            let availableWidth = max(bounds.width - spacing * CGFloat(presentCols + 1), 0)

            let cellY = y - rowHeight
            var x = bounds.minX + spacing
            for (c, idx) in rowIndices.enumerated() {
                let width = colWeights[c] / totalColWeight * availableWidth
                frames[idx] = CGRect(x: x, y: cellY, width: width, height: rowHeight)
                x += width + spacing
            }
            y = cellY - spacing
        }

        return Result(frames: frames, rowOf: rowOf, colOf: colOf, indexAt: indexAt)
    }

    /// The pane index that should gain focus moving `direction` from
    /// `index`, or `index` unchanged if there's nowhere to go that way.
    static func move(from index: Int, direction: Direction, layout: Result) -> Int {
        guard layout.rowOf.indices.contains(index) else { return index }
        let row = layout.rowOf[index]
        let col = layout.colOf[index]

        switch direction {
        case .left:
            guard col > 0 else { return index }
            return layout.indexAt[row][col - 1]
        case .right:
            guard col + 1 < layout.indexAt[row].count else { return index }
            return layout.indexAt[row][col + 1]
        case .up:
            guard row > 0 else { return index }
            let targetRow = layout.indexAt[row - 1]
            return targetRow[min(col, targetRow.count - 1)]
        case .down:
            guard row + 1 < layout.indexAt.count else { return index }
            let targetRow = layout.indexAt[row + 1]
            return targetRow[min(col, targetRow.count - 1)]
        }
    }
}
