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
use_ok qw(Bliptown::Model::TOTP);

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
my $totp		= Bliptown::Model::TOTP->new;
my $customer	= Bliptown::Model::Customer->new(
	util => $util,
);
my $user		= Bliptown::Model::User->new(
	db => $db,
	customer => $customer,
	totp => $totp
);

my $tempbase	= tempdir;
my $user_home	= $tempbase->child('users')->make_path;

$app->config->{user_home} = $user_home;

my $username	= 'testuser';
my $email		= 'testuser@example.com';
my $user_dir	= $user_home->child($username)->make_path;

$user->create_user({
    username	=> $username,
    email		=> $email,
    password	=> 'password123',
});

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#username', 'value', $username)
	->attr_is('input#email', 'value', $email)
	->attr_is('input#custom-domain', 'value', '')
	->attr_is('select#date-format option[value="0"]', 'selected', '')
	->element_exists_not('input#create-backups[checked]');

$t->post_ok($app->url_for('save_settings') => { Host => $user_domain } => form => {
	email => 'newemail@mydomain.org',
	new_password => 'newpassword456',
	custom_domain => 'mydomain.org',
	create_backups => 1,
	date_format => 2,
})->status_is(302);

$t->get_ok($app->url_for('list_settings') => { Host => $user_domain })->status_is(200)
	->attr_is('input#email', 'value', 'newemail@mydomain.org')
	->attr_is('input#custom-domain', 'value', 'mydomain.org')
	->attr_is('select#date-format option[value="2"]', 'selected', '')
	->element_exists('input#create-backups[checked]');

$t->get_ok($app->url_for('generate_totp') => { Host => $user_domain })->status_is(200)
	->attr_like('img#qrcode', 'src', qr{data:image/png;base64})
	->text_like('code#secret', qr/[A-Z2-7]{37}/)
	->attr_is('input#totp-check', 'value', '');

my $secret				= 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
my @totp_expected_pair	= $totp->read_totp({ totp_secret => $secret });

$t->post_ok($app->url_for('save_totp') => { Host => $user_domain } => form => {
	secret => $secret,
	totp => $totp_expected_pair[0],
})->status_is(302);

subtest 'save_totp' => sub {
	my $user_rec = $user->read_user({
		key			=> 'username',
		username	=> 'testuser',
	});
	is $user_rec->{totp_secret}, $secret, 'save_totp saves correct secret';
};

$user->delete_user({
	username	=> $username,
});

done_testing;
