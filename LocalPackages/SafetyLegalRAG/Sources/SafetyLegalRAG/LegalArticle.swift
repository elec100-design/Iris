import GRDB

/// Represent a single legal article chunk extracted from Korean industrial safety laws.
public struct LegalArticle: Codable, FetchableRecord, PersistableRecord, Equatable {
    public static let databaseTableName = "legalArticles"

    public var id: Int64?
    public var chunkId: String
    public var lawId: String
    public var lawTitleKo: String
    public var category: String
    public var effectiveDate: String
    public var lastAmended: String
    public var competentAuthority: String
    public var articleRef: String
    public var heading: String
    public var content: String
    public var tagsCsv: String

    public init(
        id: Int64? = nil,
        chunkId: String,
        lawId: String,
        lawTitleKo: String,
        category: String,
        effectiveDate: String,
        lastAmended: String,
        competentAuthority: String,
        articleRef: String,
        heading: String,
        content: String,
        tagsCsv: String = ""
    ) {
        self.id = id
        self.chunkId = chunkId
        self.lawId = lawId
        self.lawTitleKo = lawTitleKo
        self.category = category
        self.effectiveDate = effectiveDate
        self.lastAmended = lastAmended
        self.competentAuthority = competentAuthority
        self.articleRef = articleRef
        self.heading = heading
        self.content = content
        self.tagsCsv = tagsCsv
    }
}
