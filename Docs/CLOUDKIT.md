# Turning sync on

Everything in the app is ready for CloudKit. What is left needs an Apple
Developer account, which is why it is written down rather than done.

## What is already true

- **The schema is legal.** Every synced property is optional or defaulted, no
  uniqueness constraints, every relationship optional. `CloudKitSchemaTests`
  walks the real schema and fails the build if any of that stops being true, so
  switching mirroring on is a flag rather than a migration.
- **The split is right.** `BulletinModelContainer` puts feeds, folders, tags,
  streams, article metadata and status in the synced store, and article bodies
  and fetch bookkeeping in a `cloudKitDatabase: .none` store. Tests assert the
  two are disjoint and that `ArticleBody` is never in the synced set.
- **Dedup does not depend on the database.** CloudKit has no uniqueness
  constraint, so `(feed, guid)` dedup is enforced in `FeedStore` and tested.

## The four steps

1. **Register a container.** On the developer portal, create a CloudKit
   container named `iCloud.pizza.martin.Bulletin`. If you use a different name,
   use that name in step 2 instead.

   The container must belong to team `CQXRBQKG85`, which is what Release builds
   are already signed with.

2. **Add the two keys to the entitlements file.** `Bulletin/macOS/Bulletin.entitlements`
   is already written and already wired into both build configurations. Add:

   ```xml
   <key>com.apple.developer.icloud-services</key>
   <array><string>CloudKit</string></array>
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array><string>iCloud.pizza.martin.Bulletin</string></array>
   ```

   > This is the step that has to wait for step 1. An iCloud entitlement with no
   > registered container and no matching provisioning profile is rejected at
   > load, and the app will not launch — including the Debug build, which signs
   > ad-hoc precisely so it needs no profile.

3. **Give Debug a profile too, or stop signing it ad-hoc.** Debug currently uses
   `CODE_SIGN_IDENTITY = "-"`, which cannot carry an iCloud entitlement. Switch
   Debug to `Apple Development` with `CODE_SIGN_STYLE = Automatic` so Xcode
   provisions it.

4. **Flip the flag.** In `BulletinModelContainer`, set
   `isCloudKitMirroringEnabled = true`.

## Then check it actually works

Two Macs on one iCloud account:

- Star an article on A; it becomes starred on B.
- Subscribe to a feed on A; the feed **and its article metadata** appear on B
  without B ever having polled it.
- Open an article on B that only A has read the text of. B should extract it
  itself — **bodies must not cross**. If B shows the text instantly, something
  is syncing that should not be.
- Read a dozen articles quickly on A. B should catch up; it does not need to
  match keystroke for keystroke.

The first sync populates the CloudKit schema from the model. Deploy the schema
to production from the CloudKit console before shipping, or the first release
build will talk to an empty production database.

## What conflict resolution does

Automatic mirroring is last-writer-wins per record. For this app that is the
right behaviour and needs no code: the conflicting field is almost always
`isRead`, two devices disagreeing about it is not interesting, and the newer
answer is the one the user acted on most recently.

Nothing here merges: articles are immutable after ingest, and status records are
per-article, so two devices editing the *same* field of the *same* record is the
only conflict there is.
