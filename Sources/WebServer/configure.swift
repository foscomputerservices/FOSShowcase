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

extension DatabaseID {
    /// Admin connection used only for migrations (DDL)
    static let migrator = DatabaseID(string: "migrator")
}

// configures your application
public func configure(_ app: Application) async throws {
    SystemVersion.setCurrentVersion(.currentApplicationVersion)
    SystemVersion.setMinimumSupportedVersion(.vInitial)

    try app.initYamlLocalization(
        bundle: Bundle.module,
        resourceDirectoryName: "Resources"
    )

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    #if !DEBUG
    let dbHost = Environment.get("DATABASE_HOST") ?? "host.docker.internal"
    let dbPort = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432
    let dbName = Environment.get("DATABASE_NAME") ?? "foscs"

    // Runtime connection — openclaw_webhook (DML only)
    let pgConfig = SQLPostgresConfiguration(
        coreConfiguration: .init(
            host: dbHost, port: dbPort,
            username: Environment.get("DATABASE_USER") ?? "openclaw_webhook",
            password: Environment.get("DATABASE_PASSWORD") ?? "",
            database: dbName, tls: .disable
        ),
        searchPath: ["webhook", "public"]
    )
    app.databases.use(.postgres(configuration: pgConfig), as: .psql)

    // Migration connection — openclaw_admin (DDL)
    let migratorConfig = SQLPostgresConfiguration(
        coreConfiguration: .init(
            host: dbHost, port: dbPort,
            username: Environment.get("MIGRATION_DATABASE_USER") ?? "openclaw_admin",
            password: Environment.get("MIGRATION_DATABASE_PASSWORD") ?? "",
            database: dbName, tls: .disable
        ),
        searchPath: ["webhook", "public"]
    )
    app.databases.use(.postgres(configuration: migratorConfig), as: .migrator)

    app.migrations.add(CreateTVAlert(), to: .migrator)
    app.migrations.add(AddTVAlertIndexes(), to: .migrator)
    try await app.autoMigrate()
    #endif

    // register routes
    try routes(app)
}
