// MinHeap.swift — Generic binary min-heap.
// Used by NavigationGraph's Dijkstra (#6) and future A* over HybridAStarPlanner.
// O(log n) push / pop — replaces the earlier O(n log n)-per-step queue.sort approach.

import Foundation

struct MinHeap<Element: Comparable> {
    private var storage: [Element] = []

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }
    var peek: Element? { storage.first }

    mutating func push(_ element: Element) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> Element? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let out = storage.removeLast()
        if !storage.isEmpty { siftDown(from: 0) }
        return out
    }

    // MARK: - Internal

    private mutating func siftUp(from index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if storage[i] < storage[parent] {
                storage.swapAt(i, parent)
                i = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(from index: Int) {
        var i = index
        let n = storage.count
        while true {
            let left = 2 * i + 1
            let right = 2 * i + 2
            var smallest = i
            if left < n, storage[left] < storage[smallest] { smallest = left }
            if right < n, storage[right] < storage[smallest] { smallest = right }
            if smallest == i { break }
            storage.swapAt(i, smallest)
            i = smallest
        }
    }
}
