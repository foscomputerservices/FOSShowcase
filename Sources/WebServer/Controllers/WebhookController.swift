// WebhookController.swift
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
import Vapor

struct WebhookController: RouteCollection {
    private static let validIndicators: Set<String> = [
        "larsson_line", "gann_swing", "fifty_pct", "overbalance", "ma_crossover"
    ]

    func boot(routes: RoutesBuilder) throws {
        let webhooks = routes.grouped("webhooks")
        webhooks.post("tradingview", use: receiveTradingViewAlert)
    }

    /// Sanitize TradingView's extended symbol format.
    /// Pine Script wraps syminfo.tickerid in quotes, but for some symbols TV resolves
    /// it to ={"currency-id":"USD","symbol":"EXCHANGE:TICKER"} which breaks the JSON.
    /// The raw text looks like: "ticker":"={"currency-id":"USD","symbol":"COINEX:HONEYUSDT"}"
    /// Replace the entire quoted extended format with just "EXCHANGE:TICKER".
    private func sanitizeExtendedSymbols(in text: String) -> String {
        text.replacingOccurrences(
            of: #""=\{[^}]*"symbol":"([^"]*)"[^}]*\}""#,
            with: "\"$1\"",
            options: .regularExpression
        )
    }

    private func decodePayload(from body: String) throws -> TradingViewPayload {
        let trimmed = sanitizeExtendedSymbols(
            in: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Pure JSON — try direct decode first
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(TradingViewPayload.self, from: data) {
            return payload
        }

        // TIS-delimited format — extract secret and JSON block
        guard trimmed.contains("---TIS-ALERT-START---") else {
            throw Abort(.badRequest, reason: "Invalid payload: not JSON or TIS-delimited")
        }

        // Extract secret from "secret:VALUE"
        guard let secretRange = trimmed.range(of: #"secret:([^\s{]+)"#, options: .regularExpression) else {
            throw Abort(.badRequest, reason: "No secret found in TIS payload")
        }
        let secret = String(trimmed[secretRange].dropFirst("secret:".count))

        // Extract JSON object between first { and last }
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            throw Abort(.badRequest, reason: "No JSON block found in TIS payload")
        }
        let jsonString = String(trimmed[jsonStart...jsonEnd])

        guard let jsonData = jsonString.data(using: .utf8),
              var dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw Abort(.badRequest, reason: "Invalid JSON in TIS payload")
        }

        // Inject secret (TIS format has it outside the JSON)
        dict["secret"] = secret

        // Split "BATS:NVD" ticker into exchange + bare ticker
        if let ticker = dict["ticker"] as? String, ticker.contains(":") {
            let parts = ticker.split(separator: ":", maxSplits: 1)
            dict["exchange"] = String(parts[0])
            dict["ticker"] = String(parts[1])
        }

        // Map TradingView resolution strings to our short format
        if let tf = dict["timeframe"] as? String {
            switch tf {
            case "240": dict["timeframe"] = "4H"
            case "1D":  dict["timeframe"] = "D"
            case "1W":  dict["timeframe"] = "W"
            default: break
            }
        }

        let modifiedData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(TradingViewPayload.self, from: modifiedData)
    }

    @Sendable
    private func receiveTradingViewAlert(req: Request) async throws -> Response {
        // Force text decoding regardless of Content-Type header.
        // TradingView sends webhooks as text/plain even when the body is valid JSON,
        // and Vapor's content negotiation rejects plaintext dictionary decoding.
        guard let buffer = req.body.data else {
            throw Abort(.badRequest, reason: "Empty body")
        }
        let bodyString = String(buffer: buffer)
        let payload = try decodePayload(from: bodyString)

        // Validate webhook secret
        guard let expectedSecret = Environment.get("WEBHOOK_SECRET"),
              payload.secret == expectedSecret else {
            return Response(status: .unauthorized)
        }

        // Validate indicator
        guard Self.validIndicators.contains(payload.indicator) else {
            return Response(
                status: .badRequest,
                body: .init(string: "Invalid indicator: \(payload.indicator)")
            )
        }

        // Grace period: suppress alerts that fire within 60s of creation.
        // When create_alerts creates an alert inactive then activates it,
        // TradingView may still evaluate stale template conditions on activation.
        // The created_at timestamp lets us detect and discard these false fires.
        if let createdAtString = payload.createdAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            // Try with fractional seconds first, then without
            if let createdDate = formatter.date(from: createdAtString)
                ?? ISO8601DateFormatter().date(from: createdAtString) {
                let elapsed = Date().timeIntervalSince(createdDate)
                if elapsed >= 0 && elapsed < 60 {
                    req.logger.info("Alert suppressed (grace period): \(payload.indicator) \(payload.ticker) created \(String(format: "%.1f", elapsed))s ago")
                    return Response(status: .ok, body: .init(string: "OK (grace period)"))
                }
            }
        }

        // Encode full payload as JSON for raw_json column
        let encoder = JSONEncoder()
        let rawJSONData = try encoder.encode(payload)
        let rawJSONString = String(data: rawJSONData, encoding: .utf8) ?? "{}"

        // Extract source IP
        let sourceIP = req.headers.first(name: .xForwardedFor)
            ?? req.remoteAddress?.ipAddress

        let alert = TVAlert(
            indicator: payload.indicator,
            signal: payload.signal,
            ticker: payload.ticker,
            timeframe: payload.timeframe,
            price: payload.price,
            direction: payload.direction,
            exchange: payload.exchange,
            assetClass: payload.assetClass,
            rawJSON: rawJSONString,
            sourceIP: sourceIP
        )

        do {
            try await alert.save(on: req.db)
        } catch let error as DatabaseError where error.isConstraintFailure {
            // Dedup: return 200 OK on constraint violation
            req.logger.warning("Duplicate alert received: \(payload.ticker) \(payload.indicator)")
            return Response(status: .ok, body: .init(string: "OK (duplicate)"))
        }

        req.logger.info("Alert received: \(payload.indicator) \(payload.signal) \(payload.ticker) @ \(payload.price)")

        return Response(status: .ok, body: .init(string: "OK"))
    }
}

struct TradingViewPayload: Content {
    let secret: String
    let indicator: String
    let signal: String
    let ticker: String
    let timeframe: String
    let price: Double
    let direction: String?
    let exchange: String?
    let assetClass: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case secret, indicator, signal, ticker, timeframe, price, direction, exchange
        case assetClass = "asset_class"
        case createdAt = "created_at"
    }
}
