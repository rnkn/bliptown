use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use Bliptown::Model::TOTP;

use_ok qw(Bliptown::Model::User);

my $db		= create_db;
my $totp	= Bliptown::Model::TOTP->new;
my $user	= Bliptown::Model::User->new(db => $db, totp => $totp);

subtest 'create_user' => sub {
	$user->create_user({
		username	=> 'test_user',
		email		=> 'test_user@example.com',
		password	=> 'password123',
	});

	my $record = $db->select('users', undef, { username => 'test_user' })->hash;
	ok $record, 'create_user creates a user in database';
};

subtest 'read_user by username' => sub {
	my $record = $user->read_user({ key => 'username', username => 'test_user' });
	ok $record, 'read_user finds user by username';
	is $record->{username}, 'test_user', 'read_user username matches';
	is $record->{email}, 'test_user@example.com', 'read_user email matches';
	ok $record->{password_hash}, 'read_user password_hash is set';
	ok $record->{totp_secret}, 'read_user totp_secret is set';
};

subtest 'read_user by email' => sub {
	my $record = $user->read_user({ key => 'email', email => 'test_user@example.com' });
	ok $record, 'read_user finds user by email';
	is $record->{username}, 'test_user', 'read_user username matches';
};

subtest 'read_user with missing key returns undef' => sub {
	my $record = $user->read_user({});
	ok !defined $record, 'read_user returns undef with missing key';
};

subtest 'read_user nonexistent user returns undef' => sub {
	my $record = $user->read_user({ key => 'username', username => 'nobody' });
	ok !defined $record, 'returns undef for nonexistent user';
};

subtest 'update_user email' => sub {
	$user->update_user({ username => 'test_user', email => 'newemail@example.com' });
	my $record = $user->read_user({ key => 'username', username => 'test_user' });
	is $record->{email}, 'newemail@example.com', 'update_user updates email';
};

subtest 'update_user password' => sub {
	my $record = $user->read_user({ key => 'username', username => 'test_user' });
	my $old_password_hash = $record->{password_hash};
	$user->update_user({ username => 'test_user', new_password => 'newpassword456' });
	$record = $user->read_user({ key => 'username', username => 'test_user' });
	ok $record->{password_hash} ne $old_password_hash, 'update_user password changed';
};

subtest 'update_user custom_domain' => sub {
	$user->update_user({ username => 'test_user', custom_domain => 'mydomain.org' });
	my $record = $user->read_user({ key => 'username', username => 'test_user' });
	is $record->{custom_domain}, 'mydomain.org', 'update_user sets custom_domain';

	$user->update_user({ username => 'test_user', custom_domain => '' });
	$record = $user->read_user({ key => 'username', username => 'test_user' });
	ok !defined $record->{custom_domain}, 'custom_domain removes custom domain';
};

subtest 'update_user date_format and create_backups' => sub {
	$user->update_user({ username => 'test_user', date_format => 2, create_backups => 1 });
	my $record = $user->read_user({ key => 'username', username => 'test_user' });
	is $record->{date_format}, 2, 'update_user sets date_format';
	is $record->{create_backups}, 1, 'update_user sets create_backups';
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
	username	=> 'auth_user',
	password	=> 'correctpass123',
});

my $auth_user = $user->read_user({
	key			=> 'username',
	username	=> 'auth_user'
});

my @totp_pair = $totp->read_totp({
	totp_secret => $auth_user->{totp_secret}
});

subtest 'authenticate_user with credentials' => sub {
	my $ok = $user->authenticate_user({
		username	=> 'auth_user',
		password	=> 'correctpass123',
		totp		=> $totp_pair[0],
	});
	ok $ok, 'authenticate_user succeeds with credentials';
};

subtest 'delete_user without username' => sub {
	my $result = $user->delete_user({});
	ok !defined $result, 'delete_user without username returns undef';
};

done_testing;
