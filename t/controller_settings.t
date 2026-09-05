use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use Bliptown::Model::User;
use Bliptown::Model::Customer;
use Bliptown::Model::Util;

use FakeIPC;
use FakeDNS;

use BliptownTest qw(create_db);

use_ok qw(Bliptown::Controller::Settings);

my $t			= Test::Mojo->new('Bliptown');
my $app			= $t->app;
my $db			= create_db;
my $ipc			= FakeIPC->new;
my $dns			= FakeDNS->new;

$app->helper(
	db => sub { return $db }
);

$app->helper(
	ipc => sub { return $ipc }
);

$app->helper(
	dns => sub { return $dns }
);

my $util		= Bliptown::Model::Util->new;
my $customer	= Bliptown::Model::Customer->new(
	util => $util,
);
my $user		= Bliptown::Model::User->new(
	db => $db,
	customer => $customer,
);

$ENV{BLIPTOWN_DATA_HOME} = tempdir;

my $username	= 'testuser';
my $email		= 'testuser@example.com';
my $user_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#username', 'value', $username)
	->attr_is('input#email', 'value', $email)
	->element_exists_not('input#create-backups[checked]');

$t->post_ok($app->url_for('save_settings') => { Host => $user_domain } => form => {
	email => 'newemail@mydomain.org',
	create_backups => 1,
})->status_is(302);

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#email', 'value', 'newemail@mydomain.org')
	->element_exists('input#create-backups[checked]');

$user->delete_user({
	username	=> $username,
});

done_testing;
