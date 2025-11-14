-- 4 up
CREATE TABLE login_tokens (
    token TEXT,
    username TEXT,
    expires INTEGER
);
-- 4 down
DROP TABLE login_tokens;
-- 3 up
ALTER TABLE users
    ADD COLUMN create_backups INTEGER;
ALTER TABLE users
    ADD COLUMN sort_new INTEGER;
-- 3 down
ALTER TABLE users
    DROP COLUMN create_backups;
ALTER TABLE users
	DROP COLUMN sort_new;
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
