use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use Bliptown::Model::TOTP;
use Bliptown::Model::Util;
use Bliptown::Model::Customer;

use_ok qw(Bliptown::Model::User);

my $db			= create_db;
my $totp		= Bliptown::Model::TOTP->new;
my $util		= Bliptown::Model::Util->new;

my $customer = Bliptown::Model::Customer->new(
	util => $util,
);

my $user = Bliptown::Model::User->new(
	db => $db,
	customer => $customer,
	totp => $totp,
);

subtest 'create_user' => sub {
	$user->create_user({
		username => 'testuser',
		email => 'testuser@example.com',
		password => 'password123',
	});

	my $record_rec = $db->select('users', undef, { username => 'testuser' })->hash;
	ok $record_rec, 'create_user creates a user in database';
};

subtest 'read_user by username' => sub {
	my $record_rec = $user->read_user({
		key => 'username',
		username => 'testuser',
	});
	ok $record_rec, 'read_user finds user by username';
	is $record_rec->{username}, 'testuser', 'read_user username matches';
	is $record_rec->{email}, 'testuser@example.com', 'read_user email matches';
	ok $record_rec->{password_hash}, 'read_user password_hash is set';
	ok $record_rec->{totp_secret}, 'read_user totp_secret is set';
	ok $record_rec->{customer_id}, 'read_user customer_id is set';
};

subtest 'read_user by email' => sub {
	my $record_rec = $user->read_user({
		key => 'email',
		email => 'testuser@example.com',
	});
	ok $record_rec, 'read_user finds user by email';
	is $record_rec->{username}, 'testuser', 'read_user username matches';
};

subtest 'read_user with missing key returns undef' => sub {
	my $record_rec = $user->read_user({});
	ok !defined $record_rec, 'read_user returns undef with missing key';
};

subtest 'read_user nonexistent user returns undef' => sub {
	my $record_rec = $user->read_user({
		key => 'username',
		username => 'nobody'
	});
	ok !defined $record_rec, 'returns undef for nonexistent user';
};

subtest 'update_user email' => sub {
	$user->update_user({
		username => 'testuser',
		email => 'newemail@example.com'
	});
	my $record_rec = $user->read_user({ key => 'username', username => 'testuser' });
	is $record_rec->{email}, 'newemail@example.com', 'update_user updates email';
};

subtest 'update_user password' => sub {
	my $record_rec = $user->read_user({
		key => 'username',
		username => 'testuser',
	});
	my $old_password_hash = $record_rec->{password_hash};
	$user->update_user({
		username => 'testuser',
		new_password => 'newpassword456'
	});
	$record_rec = $user->read_user({
		key => 'username',
		username => 'testuser'
	});
	ok $record_rec->{password_hash} ne $old_password_hash, 'update_user password changed';
};

subtest 'update_user custom_domain' => sub {
	$user->update_user({
		username => 'testuser',
		custom_domain => 'mydomain.org',
	});
	my $record_rec = $user->read_user({
		key => 'username',
		username => 'testuser',
	});
	is $record_rec->{custom_domain}, 'mydomain.org', 'update_user sets custom_domain';

	$user->update_user({
		username => 'testuser',
		custom_domain => '',
	});
	$record_rec = $user->read_user({ key => 'username', username => 'testuser' });
	ok !defined $record_rec->{custom_domain}, 'custom_domain removes custom domain';
};

subtest 'update_user date_format and create_backups' => sub {
	$user->update_user({
		username => 'testuser',
		date_format => 2,
		create_backups => 1,
	});
	my $record_rec = $user->read_user({
		key => 'username',
		username => 'testuser',
	});
	is $record_rec->{date_format}, 2, 'update_user sets date_format';
	is $record_rec->{create_backups}, 1, 'update_user sets create_backups';
};

$user->create_user({
	username	=> 'demo',
	password	=> 'demo',
});

subtest 'authenticate_user demo with wrong password' => sub {
	my $result = $user->authenticate_user({
		username	=> 'demo',
		password	=> 'wrongpass',
	});
	ok !$result, 'authenticate_user demo fails with wrong password';
};

subtest 'authenticate_user demo with correct password' => sub {
	my $result = $user->authenticate_user({
		username	=> 'demo',
		password	=> 'demo',
	});
	ok $result, 'authenticate_user demo succeeds with correct password';
};

subtest 'authenticate_user for nonexistent user' => sub {
	my $result = $user->authenticate_user({
		username	=> 'nobody',
		password	=> 'whatever',
		totp		=> '000000',
	});
	ok !$result, 'authentication fails for nonexistent user';
};

$user->create_user({
	username	=> 'authuser',
	password	=> 'correctpass123',
});

my $auth_user_rec = $user->read_user({
	key			=> 'username',
	username	=> 'authuser'
});

my @totp_pair = $totp->read_totp({
	totp_secret => $auth_user_rec->{totp_secret}
});

subtest 'authenticate_user with credentials' => sub {
	my $result = $user->authenticate_user({
		username	=> 'authuser',
		password	=> 'correctpass123',
		totp		=> $totp_pair[0],
	});
	ok $result, 'authenticate_user succeeds with credentials';
};

subtest 'delete user' => sub {
	my $result = $user->delete_user({ username => 'testuser' });
	ok $result, 'delete_user succeeds';
};

subtest 'delete_user without username' => sub {
	my $result = $user->delete_user({});
	ok !defined $result, 'delete_user without username returns undef';
};

done_testing;
