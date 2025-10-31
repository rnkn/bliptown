-- 1 up
CREATE TABLE users (
    id INTEGER PRIMARY KEY autoincrement,
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
	totp_secret TEXT NOT NULL
);
-- 1 down
DROP TABLE IF EXISTS users;
