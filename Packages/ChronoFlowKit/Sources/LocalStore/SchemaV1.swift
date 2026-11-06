import GRDB

enum SchemaV1 {
    static func migrate(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE account (
                    id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, email TEXT NOT NULL,
                    has_verified_email INTEGER NOT NULL DEFAULT true, synced_at TEXT,
                    walkthrough_seen INTEGER NOT NULL DEFAULT false
                );
                CREATE TABLE trips (
                    id TEXT PRIMARY KEY NOT NULL, card TEXT NOT NULL, adaptation TEXT, form TEXT, revision TEXT,
                    current_input_hash TEXT, keep_offline INTEGER NOT NULL DEFAULT false, departure_utc TEXT NOT NULL,
                    plan_start_utc TEXT, plan_start_zone TEXT, preparation_days INTEGER, plan_end_utc TEXT,
                    plan_end_date TEXT, deleted_at TEXT, deleted_locally INTEGER NOT NULL DEFAULT false
                );
                CREATE TABLE plan_versions (
                    trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE, input_hash TEXT NOT NULL,
                    detail TEXT NOT NULL, received_at TEXT NOT NULL, detail_version TEXT,
                    PRIMARY KEY (trip_id, input_hash)
                );
                CREATE TABLE check_marks (
                    trip_id TEXT NOT NULL, input_hash TEXT NOT NULL, type TEXT NOT NULL, local_date TEXT NOT NULL,
                    ordinal INTEGER NOT NULL, status TEXT NOT NULL, marked_at TEXT NOT NULL,
                    PRIMARY KEY (trip_id, input_hash, type, local_date, ordinal)
                );
                CREATE TABLE settings (section TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
                CREATE TABLE drafts (
                    id TEXT PRIMARY KEY NOT NULL, trip_id TEXT, form TEXT NOT NULL, base_form TEXT,
                    dirty INTEGER NOT NULL DEFAULT true, review TEXT, token TEXT, input_revision INTEGER NOT NULL DEFAULT 0,
                    review_revision INTEGER, wizard_source_revision TEXT, wizard_review TEXT, furthest_step TEXT,
                    wizard_state TEXT, source_revision TEXT, save_failure TEXT, field_errors TEXT, updated_at TEXT NOT NULL
                );
                CREATE TABLE outbox (
                    id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT
                );
                """)
    }
}
