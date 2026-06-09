import GRDB

public struct SafetyLegalRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func createSchema() async throws {
        try await dbWriter.write { db in
            try db.create(table: LegalArticle.databaseTableName) { table in
                table.column("id", .integer).primaryKey()
                table.column("chunkId", .text).notNull().unique()
                table.column("lawId", .text).notNull()
                table.column("lawTitleKo", .text).notNull()
                table.column("category", .text).notNull()
                table.column("effectiveDate", .text).notNull()
                table.column("lastAmended", .text).notNull()
                table.column("competentAuthority", .text).notNull()
                table.column("articleRef", .text).notNull()
                table.column("heading", .text).notNull()
                table.column("content", .text).notNull()
                table.column("tagsCsv", .text)
            }
            try db.create(index: "legalArticles_fts",
                          on: LegalArticle.databaseTableName,
                          columns: [
                            "heading",
                            "content",
                            "tagsCsv",
                            "lawTitleKo",
                            "competentAuthority"
                          ])
        }
    }

    public func upsert(_ articles: [LegalArticle]) async throws {
        try await dbWriter.write { db in
            for article in articles {
                try article.save(db)
            }
        }
    }

    public func search(query: String,
                       limit: Int = 20,
                       offset: Int = 0) async throws -> [LegalArticle] {
        let pattern = "%\(query)%"
        return try await dbWriter.read { db in
            try LegalArticle
                .filter(
                    sql: "heading LIKE ? OR content LIKE ? OR tagsCsv LIKE ?",
                    arguments: [pattern, pattern, pattern]
                )
                .order(sql: "effectiveDate DESC")
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
}
