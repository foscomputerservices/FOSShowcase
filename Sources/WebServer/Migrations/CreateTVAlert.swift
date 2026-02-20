// CreateTVAlert.swift
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

struct CreateTVAlert: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("tv_alerts")
            .field("id", .int, .identifier(auto: true))
            .field("indicator", .string, .required)
            .field("signal", .string, .required)
            .field("ticker", .string, .required)
            .field("timeframe", .string, .required)
            .field("price", .double, .required)
            .field("direction", .string)
            .field("exchange", .string)
            .field("asset_class", .string)
            .field("raw_json", .string, .required)
            .field("processed", .bool, .required, .sql(.default(false)))
            .field("processed_at", .datetime)
            .field("delivery_status", .string, .sql(.default("pending")))
            .field("source_ip", .string)
            .field("received_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("tv_alerts").delete()
    }
}
