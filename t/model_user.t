use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use BliptownTest qw(new_sqlite_with_users);

use Bliptown::Model::TOTP;
use Bliptown::Model::User;

my $sql  = new_sqlite_with_users();
my $totp = Bliptown::Model::TOTP->new;
my $user = Bliptown::Model::User->new(sqlite => $sql, totp => $totp);

subtest 'create_user' => sub {
	$user->create_user({
		username => 'testuser',
		email    => 'testuser@example.com',
		password => 'password123',
	});

	my $record = $sql->db->select('users', undef, { username => 'testuser' })->hash;
	ok $record, 'user record exists in database';
	is $record->{username}, 'testuser', 'username matches';
	is $record->{email}, 'testuser@example.com', 'email matches';
	ok $record->{password_hash}, 'password_hash is set';
	ok $record->{totp_secret}, 'totp_secret is set';
};

subtest 'read_user by username' => sub {
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	ok $record, 'user found by username';
	is $record->{username}, 'testuser', 'username correct';
	is $record->{email}, 'testuser@example.com', 'email correct';
};

subtest 'read_user by email' => sub {
	my $record = $user->read_user({ key => 'email', email => 'testuser@example.com' });
	ok $record, 'user found by email';
	is $record->{username}, 'testuser', 'username matches when looked up by email';
};

subtest 'read_user with missing key returns undef' => sub {
	my $record = $user->read_user({});
	ok !defined $record, 'returns undef when key is missing';
};

subtest 'read_user nonexistent user returns undef' => sub {
	my $record = $user->read_user({ key => 'username', username => 'nobody' });
	ok !defined $record, 'returns undef for nonexistent user';
};

subtest 'update_user email' => sub {
	$user->update_user({ username => 'testuser', email => 'newemail@example.com' });
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	is $record->{email}, 'newemail@example.com', 'email updated successfully';
};

subtest 'update_user password' => sub {
	$user->update_user({ username => 'testuser', new_password => 'newpassword456' });
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	ok $record->{password_hash}, 'password_hash still present after update';
};

subtest 'update_user custom_domain' => sub {
	$user->update_user({ username => 'testuser', custom_domain => 'mycustom.example.com' });
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	is $record->{custom_domain}, 'mycustom.example.com', 'custom_domain set correctly';

	$user->update_user({ username => 'testuser', custom_domain => '' });
	$record = $user->read_user({ key => 'username', username => 'testuser' });
	ok !defined $record->{custom_domain}, 'custom_domain cleared to undef when empty string';
};

subtest 'update_user date_format and create_backups as integers' => sub {
	$user->update_user({ username => 'testuser', date_format => 2, create_backups => 1 });
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	is $record->{date_format}, 2, 'date_format updated';
	is $record->{create_backups}, 1, 'create_backups updated';
};

subtest 'authenticate_user with wrong password fails' => sub {
	# First, create a fresh user with a known password for auth tests
	$user->create_user({
		username => 'authuser',
		email    => 'authuser@example.com',
		password => 'correctpass',
	});
	my $result = $user->authenticate_user({
		username => 'authuser',
		password => 'wrongpass',
		totp     => '000000',
	});
	ok !$result, 'authentication fails with wrong password';
};

subtest 'authenticate_user for nonexistent user fails' => sub {
	my $result = $user->authenticate_user({
		username => 'noone',
		password => 'whatever',
		totp     => '000000',
	});
	ok !$result, 'authentication fails for nonexistent user';
};

subtest 'authenticate_user for demo user skips TOTP' => sub {
	$user->create_user({
		username => 'demo',
		email    => 'demo@example.com',
		password => 'demopassword',
	});
	my $result = $user->authenticate_user({
		username => 'demo',
		password => 'demopassword',
		totp     => '',
	});
	ok $result, 'demo user authenticates without TOTP';
};

subtest 'delete_user' => sub {
	$user->delete_user({ username => 'testuser' });
	my $record = $user->read_user({ key => 'username', username => 'testuser' });
	ok !defined $record, 'user deleted successfully';
};

subtest 'delete_user with no username returns undef' => sub {
	my $result = $user->delete_user({});
	ok !defined $result, 'delete_user returns undef when username not provided';
};

done_testing;
