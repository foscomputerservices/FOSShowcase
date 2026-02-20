// TVAlert.swift
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
import Foundation

final class TVAlert: Model, @unchecked Sendable {
    static let schema = "tv_alerts"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "indicator")
    var indicator: String

    @Field(key: "signal")
    var signal: String

    @Field(key: "ticker")
    var ticker: String

    @Field(key: "timeframe")
    var timeframe: String

    @Field(key: "price")
    var price: Double

    @OptionalField(key: "direction")
    var direction: String?

    @OptionalField(key: "exchange")
    var exchange: String?

    @OptionalField(key: "asset_class")
    var assetClass: String?

    @Field(key: "raw_json")
    var rawJSON: String

    @Field(key: "processed")
    var processed: Bool

    @OptionalField(key: "processed_at")
    var processedAt: Date?

    @OptionalField(key: "delivery_status")
    var deliveryStatus: String?

    @OptionalField(key: "source_ip")
    var sourceIP: String?

    @Timestamp(key: "received_at", on: .create)
    var receivedAt: Date?

    init() {}

    init(
        indicator: String,
        signal: String,
        ticker: String,
        timeframe: String,
        price: Double,
        direction: String? = nil,
        exchange: String? = nil,
        assetClass: String? = nil,
        rawJSON: String,
        sourceIP: String? = nil
    ) {
        self.indicator = indicator
        self.signal = signal
        self.ticker = ticker
        self.timeframe = timeframe
        self.price = price
        self.direction = direction
        self.exchange = exchange
        self.assetClass = assetClass
        self.rawJSON = rawJSON
        self.processed = false
        self.deliveryStatus = nil
        self.sourceIP = sourceIP
    }
}
