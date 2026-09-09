/// Bounded, index-addressable page storage. Empty/loading slots are not empty history.
public struct HistoryPageCache<Row> {
    public let pageSize: Int
    public let capacity: Int
    private var pages: [Int: [Row]] = [:]
    private var recency: [Int] = []
    public init(pageSize: Int = 50, capacity: Int = 4) {
        precondition(pageSize > 0 && capacity > 0)
        self.pageSize = pageSize; self.capacity = capacity
    }
    public var storedRowCount: Int { pages.values.reduce(0) { $0 + $1.count } }
    public func row(at index: Int) -> Row? {
        guard index >= 0, let page = pages[index / pageSize], index % pageSize < page.count else { return nil }
        return page[index % pageSize]
    }
    public mutating func insert(_ rows: [Row], offset: Int, protecting visibleIndices: Set<Int> = []) {
        precondition(offset >= 0 && offset % pageSize == 0 && rows.count <= pageSize)
        let key = offset / pageSize
        pages[key] = rows; touch(index: offset)
        let protectedPages = Set(visibleIndices.filter { $0 >= 0 }.map { $0 / pageSize })
        while recency.count > capacity {
            // A late off-screen response must not displace the page the user is reading.
            let victim = recency.firstIndex { !protectedPages.contains($0) } ?? 0
            pages.removeValue(forKey: recency.remove(at: victim))
        }
    }
    public mutating func touch(index: Int) {
        let key = index / pageSize
        guard pages[key] != nil else { return }
        recency.removeAll { $0 == key }; recency.append(key)
    }
    public mutating func clear() { pages.removeAll(); recency.removeAll() }
}
