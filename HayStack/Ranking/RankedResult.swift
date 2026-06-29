import Foundation

struct RankedResult: Identifiable, Hashable {
    let path: String
    let rank: Int
    let reason: String
    let filename: String
    let parentPath: String
    let sizeBytes: Int?
    let modifiedDate: Date?
    let contentType: String?

    var id: String { path }

    init(from searchResult: SearchResult, rank: Int, reason: String) {
        self.path = searchResult.path
        self.rank = rank
        self.reason = reason
        self.filename = searchResult.filename
        self.parentPath = (searchResult.path as NSString).deletingLastPathComponent
        self.sizeBytes = searchResult.sizeBytes
        self.modifiedDate = searchResult.modifiedDate
        self.contentType = searchResult.contentType
    }

    init(from searchResult: SearchResult, rank: Int) {
        self.init(from: searchResult, rank: rank, reason: "")
    }
}
