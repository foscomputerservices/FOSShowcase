// configure.swift
//
// Copyright 2024 FOS Computer Services, LLC
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
import FluentPostgresDriver
import FOSFoundation
import FOSMVVM
import Foundation
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    SystemVersion.setCurrentVersion(.currentApplicationVersion)
    SystemVersion.setMinimumSupportedVersion(.vInitial)

    try app.initYamlLocalization(
        bundle: Bundle.module,
        resourceDirectoryName: "Resources"
    )

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // PostgreSQL via SSH tunnel (host.docker.internal -> Pi host -> fos-openclaw)
    let pgConfig = SQLPostgresConfiguration(
        coreConfiguration: .init(
            host: Environment.get("DATABASE_HOST") ?? "host.docker.internal",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DATABASE_USER") ?? "openclaw_webhook",
            password: Environment.get("DATABASE_PASSWORD") ?? "",
            database: Environment.get("DATABASE_NAME") ?? "foscs",
            tls: .disable
        ),
        searchPath: ["webhook", "public"]
    )
    app.databases.use(.postgres(configuration: pgConfig), as: .psql)

    app.migrations.add(CreateTVAlert())
    try await app.autoMigrate()

    // register routes
    try routes(app)
}
