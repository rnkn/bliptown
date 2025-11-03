-- 2 up
ALTER TABLE users
    ADD COLUMN custom_domain TEXT;
CREATE UNIQUE INDEX custom_domain_index ON users(custom_domain);
-- 2 down
ALTER TABLE users
    DROP COLUMN custom_domain;
-- 1 up
CREATE TABLE users (
	username TEXT,
    email TEXT,
    password_hash TEXT,
	totp_secret TEXT
);
CREATE UNIQUE INDEX username_index ON users(username);
CREATE UNIQUE INDEX email_index ON users(email);
-- 1 down
DROP TABLE users;
