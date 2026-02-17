// AddTVAlertIndexes.swift
//
// Copyright 2026 FOS Computer Services, LLC
//
// Licensed under the Apache License, Version 2.0 (the  License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Fluent
import SQLKit

struct AddTVAlertIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Unprocessed alerts (most common agent query)
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_tv_alerts_unprocessed
                ON tv_alerts (received_at DESC) WHERE NOT processed
            """).run()

        // Ticker lookup
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_tv_alerts_ticker
                ON tv_alerts (ticker, received_at DESC)
            """).run()

        // Indicator lookup
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_tv_alerts_indicator
                ON tv_alerts (indicator, received_at DESC)
            """).run()

        // General time-ordered lookup
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_tv_alerts_received
                ON tv_alerts (received_at DESC)
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("DROP INDEX IF EXISTS idx_tv_alerts_unprocessed").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_tv_alerts_ticker").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_tv_alerts_indicator").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_tv_alerts_received").run()
    }
}
