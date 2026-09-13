use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;
use FakeEmail;

use Bliptown::Model::User;
use Bliptown::Model::Token;
use Bliptown::Model::Util;

use BliptownTest qw(create_db);

use_ok qw(Bliptown::Controller::Users);

my $t		= Test::Mojo->new('Bliptown');
my $app		= $t->app;
my $db		= create_db;
my $ipc		= FakeIPC->new;
my $email	= FakeEmail->new;

$app->helper(db => sub { return $db });
$app->helper(ipc => sub { return $ipc });
$app->helper(email => sub { return $email });

my $util	= Bliptown::Model::Util->new;
my $user	= Bliptown::Model::User->new(db => $db);
my $token	= Bliptown::Model::Token->new(db => $db);

$app->helper(user => sub { return $user });
$app->helper(token => sub { return $token });
$app->helper(util => sub { return $util });

$ENV{BLIPTOWN_DATA_HOME} = tempdir;
$ENV{BLIPTOWN_DEMO_USER} = 'demo';

my $host		= $ENV{BLIPTOWN_DOMAIN};
my $mayor_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', 'mayor')->make_path;
$mayor_home->child('_title.txt')->spew("Mayor's Site");

subtest 'user_login renders message' => sub {
	$t->get_ok('/_login' => { Host => $host })->status_is(200)
		->text_like('main p', qr/Check your email for a login link/);
};

subtest 'generate_login sends magic link for known user' => sub {
	$db->insert('users', { username => 'alice', email => 'alice@example.com' });
	$email->{sent} = [];

	$t->post_ok('/_login' => { Host => $host } => form => { username => 'alice' })
		->status_is(302);
	is $t->tx->res->headers->location, '/_login',
		'generate_login redirects to user_login';
	is scalar(@{$email->{sent}}), 1, 'send_magic_link was called once';
	is $email->{sent}[0]{username}, 'alice',
		'send_magic_link received the username';
};

subtest 'generate_login demo user sets session and redirects' => sub {
	$t->post_ok('/_login' => { Host => $host } => form => {
		username	=> 'demo',
		back_to		=> '/demo-home',
	})->status_is(302);
	is $t->tx->res->headers->location, '/demo-home',
		'generate_login redirects demo user to back_to';
	ok $t->tx->res->cookie('mojolicious'),
		'generate_login sets a session cookie for demo user';
};

subtest 'user_auth with missing token is forbidden' => sub {
	$t->get_ok('/_auth' => { Host => $host })->status_is(403)
		->text_like('main p', qr/403 Forbidden/);
};

subtest 'user_auth with invalid token is forbidden' => sub {
	$t->get_ok('/_auth' => { Host => $host } => form => { token => 'doesnotexist' })
		->status_is(403)
		->text_like('main p', qr/invalid or expired token/);
};

subtest 'user_auth with expired token is forbidden and deletes token' => sub {
	my $tk = $token->create_login_token({ username => 'alice' });
	$db->update('login_tokens', { expires => time - 1 }, { token => $tk });
	ok $token->read_login_token({ token => $tk }), 'token exists before auth';

	$t->get_ok("/_auth?token=$tk" => { Host => $host })->status_is(403)
		->text_like('main p', qr/invalid or expired token/);
	ok !$token->read_login_token({ token => $tk }),
		'expired token is deleted after auth attempt';
};

subtest 'user_auth with valid token sets session and redirects' => sub {
	my $tk = $token->create_login_token({ username => 'alice' });

	$t->get_ok("/_auth?token=$tk&back_to=/somewhere" => { Host => $host })
		->status_is(302);
	is $t->tx->res->headers->location, '/somewhere',
		'user_auth redirects to back_to for valid token';
	ok $t->tx->res->cookie('mojolicious'),
		'user_auth sets a session cookie';
	ok !$token->read_login_token({ token => $tk }),
		'user_auth deletes token after use';
};

subtest 'user_auth custom domain redirects to custom host' => sub {
	my $tk = $token->create_login_token({
		username		=> 'bob',
		custom_domain	=> 'bob.example.com',
	});

	$t->get_ok("/_auth?token=$tk" => { Host => $host })
		->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{^https?://bob\.example\.com(?::\d+)?/_auth\?token=$tk$},
		'user_auth redirects to custom domain when host differs';
	ok $token->read_login_token({ token => $tk }),
		'user_auth keeps token when redirecting to custom domain';
};

subtest 'user_auth on custom host sets session and redirects home' => sub {
	my $tk = $token->create_login_token({
		username		=> 'bob',
		custom_domain	=> 'bob.example.com',
	});

	$t->get_ok("/_auth?token=$tk" => { Host => 'bob.example.com' })
		->status_is(302);
	is $t->tx->res->headers->location, '/',
		'user_auth redirects to / when host matches custom domain';
	ok $t->tx->res->cookie('mojolicious'),
		'user_auth sets session on custom host';
	ok !$token->read_login_token({ token => $tk }),
		'user_auth deletes token on custom host match';
};

subtest 'generate_logout without session redirects home' => sub {
	$t->reset_session;
	$t->post_ok('/_generate_logout' => { Host => $host })->status_is(302);
	is $t->tx->res->headers->location, '/',
		'generate_logout redirects to / without a session';
};

subtest 'generate_logout without custom domain redirects to logout url' => sub {
	$t->app->hook(before_dispatch => sub {
		my $c = shift;
		$c->session(username => 'alice');
		return 1;
	});

	$t->post_ok('/_generate_logout' => { Host => $host } => form => { back_to => '/home' })
		->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{/_logout}, 'generate_logout redirects to logout route';
	like $loc, qr{back_to=%2Fhome}, 'generate_logout preserves back_to';
	unlike $loc, qr{token=},
		'generate_logout omits token without custom domain';
};

subtest 'generate_logout with custom domain creates logout token' => sub {
	$t->app->hook(before_dispatch => sub {
		my $c = shift;
		$c->session(username => 'carol');
		return 1;
	});
	my $carol_home = path($ENV{BLIPTOWN_DATA_HOME}, 'users', 'carol')->make_path;
	$carol_home->child('_domain.txt')->spew("carol.example.com\n");

	$t->post_ok('/_generate_logout' => { Host => $host } => form => { back_to => '/page' })
		->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{token=}, 'generate_logout includes token for custom domain';
	my ($tk) = $loc =~ m{[?&]token=([^&]+)};
	ok $token->read_logout_token({ token => $tk }),
		'generate_logout persists a logout token';
};

subtest 'user_logout expires session and redirects to back_to' => sub {
	$t->app->hook(before_dispatch => sub {
		my $c = shift;
		$c->session(username => 'alice');
		return 1;
	});

	$t->post_ok('/_logout' => { Host => $host } => form => { back_to => '/done' })
		->status_is(302);
	is $t->tx->res->headers->location, '/done',
		'user_logout redirects to back_to without custom domain';
	ok $t->tx->res->cookie('mojolicious')->expires,
		'user_logout expires the session';
};

subtest 'user_logout with logout token redirects across custom domain' => sub {
	$t->app->hook(before_dispatch => sub {
		my $c = shift;
		$c->session(username => 'dave');
		return 1;
	});
	my $tk = $token->create_logout_token({
		username		=> 'dave',
		custom_domain	=> 'dave.example.com',
	});

	$t->post_ok("/_logout?token=$tk" => { Host => $host }
			=> form => { back_to => '/leave' })
		->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{dave\.example\.com}, 'user_logout redirects to custom domain host';
	like $loc, qr{/_logout}, 'user_logout redirects to logout route on custom host';
};

done_testing;
