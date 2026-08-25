//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData

/// The app's two SwiftData stores.
///
/// Splitting them is what makes "sync my subscriptions and reading state, but
/// not gigabytes of article text" expressible at all: CloudKit mirroring is a
/// property of a `ModelConfiguration`, not of an individual model.
///
/// - **Synced store** — feeds, folders, tags, streams, article metadata and
///   status. Mirrored to CloudKit.
/// - **Local store** — article bodies and fetch bookkeeping. Never leaves the
///   machine.
///
/// The synced models are written to CloudKit's constraints from the start —
/// every property optional or defaulted, no unique attributes — even while
/// mirroring is off, because retrofitting those constraints later is a
/// migration through CloudKit rather than a local one.
///
enum BulletinModelContainer {

    /// Models that sync.
    static let syncedModels: [any PersistentModel.Type] = [
        Feed.self,
        Folder.self,
        Article.self,
        ArticleStatus.self,
        Tag.self,
        Stream.self
    ]

    /// Models that stay on this machine.
    static let localModels: [any PersistentModel.Type] = [
        ArticleBody.self,
        FeedFetchState.self
    ]

    /// Whether the synced store actually mirrors to CloudKit yet.
    ///
    /// - Note: Off until the sync phase. The schema is already CloudKit-legal,
    ///   so switching this on is not a migration.
    static let isCloudKitMirroringEnabled = false

    static func make(inMemory: Bool = false) throws -> ModelContainer {

        let schema = Schema(syncedModels + localModels)

        let synced = ModelConfiguration(
            "Synced",
            schema: Schema(syncedModels),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: isCloudKitMirroringEnabled ? .automatic : .none
        )

        let local = ModelConfiguration(
            "Local",
            schema: Schema(localModels),
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: synced, local)
    }
}
