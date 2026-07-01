import Foundation
import SQLite3

/// 캡처의 OCR 텍스트·태그·임베딩을 SQLite 에 저장하고 검색한다.
/// (시스템 libsqlite3 직접 사용 — 외부 의존성 없음)
final class SearchIndex {
    struct Result {
        let path: String
        let capturedAt: Date
        let ocr: String
        let tags: String
        let caption: String   // VLM 이 생성한 맥락 설명 (없으면 빈 문자열)
    }

    private var db: OpaquePointer?
    private let dbURL: URL
    private let queue = DispatchQueue(label: "com.terrykim.smartcapture.index")
    // 바인딩한 문자열을 SQLite 가 복사하도록 한다.
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) {
        dbURL = directory.appendingPathComponent("index.sqlite")
        queue.sync { openAndMigrate() }
    }

    private func openAndMigrate() {
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            NSLog("[SmartCapture] 인덱스 DB 열기 실패: \(dbURL.path)")
            return
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS screenshots (
            path        TEXT PRIMARY KEY,
            captured_at REAL NOT NULL,
            ocr         TEXT,
            tags        TEXT,
            caption     TEXT,
            embedding   BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_captured_at ON screenshots(captured_at);
        """
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            NSLog("[SmartCapture] 스키마 생성 오류: \(String(cString: err))")
            sqlite3_free(err)
        }
        // 기존 DB 마이그레이션: caption 컬럼이 없으면 추가 (이미 있으면 오류 무시).
        sqlite3_exec(db, "ALTER TABLE screenshots ADD COLUMN caption TEXT;", nil, nil, nil)
    }

    /// VLM 캡션을 나중에 채워 넣는다(OCR 색인 후 비동기로 도착).
    func updateCaption(path: String, caption: String) {
        queue.async {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db,
                "UPDATE screenshots SET caption = ? WHERE path = ?;", -1, &stmt, nil) == SQLITE_OK
            else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, caption, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, path, -1, self.SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// 캡처 분석 결과를 인덱스에 추가/갱신한다.
    func index(path: String, capturedAt: Date, ocr: String, tags: [String], embedding: [Float]) {
        queue.async {
            let sql = """
            INSERT OR REPLACE INTO screenshots (path, captured_at, ocr, tags, embedding)
            VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, path, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, capturedAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, ocr, -1, self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, tags.joined(separator: ", "), -1, self.SQLITE_TRANSIENT)
            let blob = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
            _ = blob.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(blob.count), self.SQLITE_TRANSIENT)
            }
            sqlite3_step(stmt)
        }
    }

    /// 휴지통으로 옮겨진 캡처를 인덱스에서 제거한다.
    func remove(path: String) {
        queue.async {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, "DELETE FROM screenshots WHERE path = ?;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, path, -1, self.SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    /// OCR 텍스트·태그를 부분일치(LIKE)로 검색한다. 빈 질의는 최근 순으로 반환.
    /// LIKE 부분일치는 한국어에도 안정적으로 동작한다.
    func search(_ query: String, limit: Int = 80) -> [Result] {
        queue.sync {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var results: [Result] = []
            var stmt: OpaquePointer?

            let sql: String
            if trimmed.isEmpty {
                sql = "SELECT path, captured_at, ocr, tags, caption FROM screenshots ORDER BY captured_at DESC LIMIT ?;"
            } else {
                sql = """
                SELECT path, captured_at, ocr, tags, caption FROM screenshots
                WHERE ocr LIKE ?1 OR tags LIKE ?1 OR caption LIKE ?1
                ORDER BY captured_at DESC LIMIT ?2;
                """
            }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return results }
            defer { sqlite3_finalize(stmt) }

            if trimmed.isEmpty {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            } else {
                sqlite3_bind_text(stmt, 1, "%\(trimmed)%", -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }

            var missingPaths: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                guard !path.isEmpty else { continue }
                // 사용자가 Finder 등에서 직접 지운 파일은 결과에서 제외하고, 인덱스에서도 정리.
                guard FileManager.default.fileExists(atPath: path) else {
                    missingPaths.append(path)
                    continue
                }
                let at = sqlite3_column_double(stmt, 1)
                let ocr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let tags = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let caption = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                results.append(Result(
                    path: path,
                    capturedAt: Date(timeIntervalSince1970: at),
                    ocr: ocr,
                    tags: tags,
                    caption: caption))
            }
            sqlite3_finalize(stmt)
            stmt = nil
            deleteRows(missingPaths)   // 없는 파일 행을 즉시 제거
            return results
        }
    }

    /// 인덱스 전체를 훑어 실제로 존재하지 않는 파일의 행을 제거한다.
    /// (폴더 감시/앱 시작 시 호출 — 검색을 열지 않아도 인덱스를 깨끗하게 유지)
    func pruneMissing() {
        queue.async {
            var paths: [String] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "SELECT path FROM screenshots;", -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let c = sqlite3_column_text(stmt, 0) { paths.append(String(cString: c)) }
                }
            }
            sqlite3_finalize(stmt)
            let missing = paths.filter { !FileManager.default.fileExists(atPath: $0) }
            self.deleteRows(missing)
            if !missing.isEmpty {
                NSLog("[SmartCapture] 삭제된 파일 \(missing.count)개를 인덱스에서 제거했습니다.")
            }
        }
    }

    /// 주어진 경로들의 행을 삭제한다. 반드시 queue 위에서 호출할 것.
    private func deleteRows(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        for path in paths {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM screenshots WHERE path = ?;", -1, &stmt, nil) == SQLITE_OK
            else { continue }
            sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
}
