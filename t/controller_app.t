use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;
use FakeDNS;

use BliptownTest qw(create_db);

use_ok qw(Bliptown::Controller::Pages);
use_ok qw(Bliptown::Controller::Analytics);

my $t		= Test::Mojo->new('Bliptown');
my $app		= $t->app;
my $db		= create_db;
my $ipc		= FakeIPC->new;
my $dns		= FakeDNS->new;

$app->helper(db => sub { return $db });
$app->helper(ipc => sub { return $ipc });
$app->helper(dns => sub { return $dns });

$ENV{BLIPTOWN_DATA_HOME}	= tempdir;
$ENV{BLIPTOWN_LOG_HOME}		= tempdir;
$ENV{BLIPTOWN_THEME_USER}	= 'themes';

my $username	= 'testuser';
my $user_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
my $user_domain	= "$username.$ENV{BLIPTOWN_DOMAIN}";

my $session_user;
$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $session_user) if defined $session_user;
	return 1;
});

sub set_session { $session_user = shift }
sub clear_session { $session_user = undef; $t->reset_session }

subtest 'acme_challenge not found' => sub {
	$t->get_ok('/.well-known/acme-challenge/missing-token' => { Host => $user_domain })
		->status_is(404);
};

subtest 'render_style returns user stylesheet' => sub {
	$user_home->child('style.css')->spew("body { color: red; }\n");

	$t->get_ok('/style.css' => { Host => $user_domain })->status_is(200)
		->content_like(qr/color:\s*red/);
};

subtest 'render_style not found without file' => sub {
	$user_home->child('style.css')->remove;

	$t->get_ok('/style.css' => { Host => $user_domain })->status_is(404);
};

subtest 'render_style theme serves shared theme' => sub {
	my $theme_home = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $ENV{BLIPTOWN_THEME_USER})
		->make_path;
	$theme_home->child('dark.css')->spew("body { background: #000; }\n");

	$t->get_ok('/style.css' => { Host => $user_domain } => form => { theme => 'dark' })
		->status_is(200)
		->content_like(qr/background:\s*#000/);
};

subtest 'my_site redirects to login without session' => sub {
	clear_session;
	$t->get_ok('/mysite' => { Host => $user_domain })->status_is(302);
	is $t->tx->res->headers->location, '/',
		'my_site redirects to / without a session';
};

subtest 'my_site redirects to user subdomain with session' => sub {
	set_session($username);

	$t->get_ok('/mysite' => { Host => $user_domain })->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{\Q$username.$ENV{BLIPTOWN_DOMAIN}\E},
		'my_site redirects to the user subdomain';
};

subtest 'my_site redirects to custom domain when configured' => sub {
	$user_home->child('_domain.txt')->spew("custom.example.org\n");

	$t->get_ok('/mysite' => { Host => $user_domain })->status_is(302);
	my $loc = $t->tx->res->headers->location;
	like $loc, qr{custom\.example\.org},
		'my_site redirects to the custom domain';
};

subtest 'protected route 403 without session' => sub {
	clear_session;

	$t->get_ok('/_files' => { Host => $user_domain })->status_is(403)
		->text_like('main p', qr/requires a login/);
};

subtest 'protected route 403 for non-owner' => sub {
	set_session('someoneelse');

	$t->get_ok('/_files' => { Host => $user_domain })->status_is(403)
		->text_like('main p', qr/requires a login/);
};

subtest 'protected route allowed for owner' => sub {
	set_session($username);

	$t->get_ok('/_files' => { Host => $user_domain })->status_is(200);
};

subtest 'block_demo forbids settings save for demo user' => sub {
	set_session($ENV{BLIPTOWN_DEMO_USER});
	my $demo_home = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $ENV{BLIPTOWN_DEMO_USER})
		->make_path;
	my $demo_domain = "$ENV{BLIPTOWN_DEMO_USER}.$ENV{BLIPTOWN_DOMAIN}";

	$t->post_ok('/_settings' => { Host => $demo_domain } => form => { email => 'demo@example.com' })
		->status_is(403)
		->text_like('main p', qr/demo user cannot perform this action/);
};

subtest 'non-cdn origin sets no-cache' => sub {
	$user_home->child('page.md')->spew("# Hi");

	$t->get_ok('/page' => { Host => $user_domain });
	is $t->tx->res->headers->cache_control, 'no-cache',
		'non-cdn origin sets no-cache';
};

subtest 'track_visit not found without resolvable user' => sub {
	$t->get_ok('/track/12345' => { Host => "nonexistent.$ENV{BLIPTOWN_DOMAIN}" })
		->status_is(404);
};

subtest 'track_visit renders empty body for self visit' => sub {
	set_session($username);

	$t->get_ok('/track/12345' => { Host => $user_domain })->status_is(200)
		->content_is('');
};

done_testing;
