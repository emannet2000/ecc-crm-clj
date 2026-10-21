CREATE TABLE user_access (
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 access_level TEXT NOT NULL CHECK(access_level IN ('all','assigned')),
 privileges TEXT NOT NULL CHECK(json_valid(privileges) AND json_type(privileges)='array'),
 revision INTEGER NOT NULL DEFAULT 1
);
