import Foundation

struct SearchResult: Identifiable, Sendable {
    let path: String
    var id: String { path }
    var filename: String
    var sizeBytes: Int?
    var modifiedDate: Date?
    var contentType: String?

    init(path: String) {
        self.path = path
        self.filename = (path as NSString).lastPathComponent
    }
}
