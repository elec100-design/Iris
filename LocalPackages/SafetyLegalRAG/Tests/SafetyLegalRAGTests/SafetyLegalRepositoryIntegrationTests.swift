import XCTest
import GRDB
@testable import SafetyLegalRAG

final class SafetyLegalRepositoryIntegrationTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: SafetyLegalRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbQueue = try DatabaseQueue(named: ":memory:")
        repository = SafetyLegalRepository(dbWriter: dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        try super.tearDownWithError()
    }

    func test_createSchema_createsTable() async throws {
        try await repository.createSchema()

        let rowCount = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='legalArticles'")
        }

        XCTAssertEqual(rowCount, 1)
    }

    func test_search_returnsKoreanArticle() async throws {
        try await repository.createSchema()

        let article = LegalArticle(
            chunkId: "OSH_INT_001",
            lawId: "OSH_INT",
            lawTitleKo: "통합 산업안전보건법 샘플",
            category: "industrial_safety",
            effectiveDate: "2024-01-01",
            lastAmended: "2023-12-26",
            competentAuthority: "고용노동부",
            articleRef: "제1조-제5조",
            heading: "안전보건교육 세부 기준",
            content: "신규 채용 시 8시간 안전보건교육을 실시하여야 하고 교육기록을 3년간 보존한다.",
            tagsCsv: "교육,채용,안전보건교육"
        )

        try await repository.upsert([article])

        let results = try await repository.search(query: "안전보건교육", limit: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.chunkId, "OSH_INT_001")
        XCTAssertEqual(results.first?.articleRef, "제1조-제5조")
    }
}
