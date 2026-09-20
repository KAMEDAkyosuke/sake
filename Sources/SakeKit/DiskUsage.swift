import Foundation

public enum DiskUsage {
    /// What the tree at `url` occupies, as the sum of what its files have allocated.
    ///
    /// A block shared with a clone is counted in full and counted again in the other tree,
    /// so this is what a directory *looks* like rather than what removing it would return.
    /// An imported game is the whole of that gap: see docs/layout.md.
    public static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        else { return 0 }

        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, let bytes = values.fileAllocatedSize
            else { continue }
            total += Int64(bytes)
        }
        return total
    }
}
