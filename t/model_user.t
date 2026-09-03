use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use Bliptown::Model::Util;
use Bliptown::Model::Customer;

use_ok qw(Bliptown::Model::User);

my $db			= create_db;
my $util		= Bliptown::Model::Util->new;

my $customer = Bliptown::Model::Customer->new(
	util => $util,
);

my $user = Bliptown::Model::User->new(
	db => $db,
	customer => $customer,
);

subtest 'create_user' => sub {
	$user->create_user({
		username => 'newuser',
		email => 'newuser@example.com',
	});

	my $user_rec = $db->select('users', undef, { username => 'newuser' })->hash;
	ok $user_rec, 'create_user creates a user in database';
};

subtest 'read_user by username' => sub {
	my $user_rec = $user->read_user({
		key => 'username',
		username => 'newuser',
	});
	ok $user_rec, 'read_user finds user by username';
	is $user_rec->{username}, 'newuser', 'read_user username matches';
	is $user_rec->{email}, 'newuser@example.com', 'read_user email matches';
	ok $user_rec->{customer_id}, 'read_user customer_id is set';
};

subtest 'read_user by email' => sub {
	my $user_rec = $user->read_user({
		key => 'email',
		email => 'newuser@example.com',
	});
	ok $user_rec, 'read_user finds user by email';
	is $user_rec->{username}, 'newuser', 'read_user username matches';
};

subtest 'read_user with missing key returns undef' => sub {
	my $user_rec = $user->read_user({});
	ok !defined $user_rec, 'read_user returns undef with missing key';
};

subtest 'read_user nonexistent user returns undef' => sub {
	my $user_rec = $user->read_user({
		key => 'username',
		username => 'nobody'
	});
	ok !defined $user_rec, 'returns undef for nonexistent user';
};

subtest 'update_user email' => sub {
	$user->update_user({
		username => 'newuser',
		email => 'newemail@example.com'
	});
	my $user_rec = $user->read_user({ key => 'username', username => 'newuser' });
	is $user_rec->{email}, 'newemail@example.com', 'update_user updates email';
};

subtest 'update_user create_backups' => sub {
	$user->update_user({
		username => 'newuser',
		create_backups => 1,
	});
	my $user_rec = $user->read_user({
		key => 'username',
		username => 'newuser',
	});
	is $user_rec->{create_backups}, 1, 'update_user sets create_backups';
};

subtest 'delete user' => sub {
	my $result = $user->delete_user({ username => 'newuser' });
	ok $result, 'delete_user succeeds';
};

subtest 'delete_user without username' => sub {
	my $result = $user->delete_user({});
	ok !defined $result, 'delete_user without username returns undef';
};

done_testing;
