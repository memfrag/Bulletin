//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Bulletin

/// Holds the synced models to CloudKit's rules.
///
/// Automatic mirroring refuses to load a store whose schema it cannot express,
/// and the failure arrives at launch on the user's machine rather than here.
/// Worse, the models were written to these rules from day one *specifically*
/// so that switching mirroring on later would not be a migration — a rule
/// broken quietly in the meantime would throw that away.
///
/// So this walks the real schema rather than trusting the comments on it.
@MainActor
@Suite("CloudKit schema rules")
struct CloudKitSchemaTests {

    private var syncedSchema: Schema {
        Schema(BulletinModelContainer.syncedModels)
    }

    @Test("Every synced attribute is optional or has a default")
    func attributesAreOptionalOrDefaulted() {
        for entity in syncedSchema.entities {
            for attribute in entity.attributes where !attribute.isTransient {
                let isLegal = attribute.isOptional || attribute.defaultValue != nil
                #expect(
                    isLegal,
                    "\(entity.name).\(attribute.name) is neither optional nor defaulted, which CloudKit mirroring cannot represent"
                )
            }
        }
    }

    @Test("No synced attribute is marked unique")
    func noUniqueAttributes() {
        // CloudKit has no uniqueness constraint, so article dedup by
        // (feed, guid) is enforced in `FeedStore` instead. A stray `.unique`
        // here would make the store refuse to load once mirroring is on.
        for entity in syncedSchema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is marked unique")
            }
            #expect(
                entity.uniquenessConstraints.isEmpty,
                "\(entity.name) declares uniqueness constraints: \(entity.uniquenessConstraints)"
            )
        }
    }

    @Test("Every synced relationship is optional")
    func relationshipsAreOptional() {
        // Mirroring populates a record's relationships as the related records
        // arrive, so every one of them is briefly absent. A non-optional
        // relationship cannot survive that window.
        for entity in syncedSchema.entities {
            for relationship in entity.relationships {
                #expect(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) is a non-optional relationship"
                )
            }
        }
    }

    @Test("The synced and local stores do not share a model")
    func storesAreDisjoint() {
        // The whole point of two configurations is that bodies stay local. A
        // model in both would be mirrored, which is precisely what D2 says must
        // not happen.
        let synced = Set(BulletinModelContainer.syncedModels.map { String(describing: $0) })
        let local = Set(BulletinModelContainer.localModels.map { String(describing: $0) })

        #expect(synced.isDisjoint(with: local))
    }

    @Test("Article bodies are in the local store, never the synced one")
    func bodiesAreLocal() {
        let syncedNames = BulletinModelContainer.syncedModels.map { String(describing: $0) }

        // Named explicitly rather than derived, so that moving `ArticleBody`
        // into the synced store has to be a deliberate act that fails here.
        #expect(!syncedNames.contains("ArticleBody"))
        #expect(!syncedNames.contains("FeedFetchState"))
    }

    @Test("The synced store carries exactly the models D2 names")
    func syncedModelsAreAsSpecified() {
        let names = Set(BulletinModelContainer.syncedModels.map { String(describing: $0) })
        #expect(names == ["Feed", "Folder", "Article", "ArticleStatus", "Tag", "Stream"])
    }
}
