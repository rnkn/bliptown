-- 10 up
CREATE TABLE logout_tokens (
	token TEXT,
	username TEXT,
	custom_domain TEXT,
	expires INTEGER
);
-- 10 down
DROP TABLE logout_tokens;
-- 9 up
ALTER TABLE users
	DROP COLUMN password_hash;
ALTER TABLE users
	DROP COLUMN totp_secret;
-- 9 down
ALTER TABLE login_tokens
	ADD COLUMN password_hash TEXT;
ALTER TABLE login_tokens
	ADD COLUMN totp_secret TEXT;
-- 8 up
ALTER TABLE login_tokens
	ADD COLUMN custom_domain TEXT;
-- 8 down
ALTER TABLE login_tokens
	DROP COLUMN custom_domain;
-- 7 up
ALTER TABLE users
	ADD COLUMN email_verified INTEGER DEFAULT 0;
ALTER TABLE users
	ADD COLUMN customer_id TEXT DEFAULT NULL;
-- 7 down
ALTER TABLE users
	DROP COLUMN email_verified;
ALTER TABLE users
	DROP COLUMN customer_id;
-- 6 up
ALTER TABLE users
	ADD COLUMN date_format INTEGER DEFAULT 0;
-- 6 down
ALTER TABLE users
	DROP COLUMN date_format;
-- 5 up
ALTER TABLE users
	DROP COLUMN sort_new;
-- 5 down
ALTER TABLE users
	ADD COLUMN sort_new INTEGER DEFAULT 0;
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
	ADD COLUMN create_backups INTEGER DEFAULT 0;
ALTER TABLE users
	ADD COLUMN sort_new INTEGER DEFAULT 0;
-- 3 down
ALTER TABLE users
	DROP COLUMN create_backups;
ALTER TABLE users
	DROP COLUMN sort_new;
-- 2 up
ALTER TABLE users
	ADD COLUMN custom_domain TEXT DEFAULT NULL;
CREATE UNIQUE INDEX custom_domain_index ON users(custom_domain);
-- 2 down
DROP INDEX IF EXISTS custom_domain_index;
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
DROP INDEX IF EXISTS username_index;
DROP INDEX IF EXISTS email_index;
DROP TABLE users;
