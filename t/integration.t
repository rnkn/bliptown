use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use Mojo::File qw(path);

BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use BliptownTest qw(setup_test_env);
use Test::Mojo;

my $env = setup_test_env();

# Create the mayor user site with some content
my $mayor_dir = path($env->{user_home}, 'mayor');
$mayor_dir->make_path;
path($mayor_dir, 'index.md')->spew(
	"---\ntitle: Home\n---\n\nWelcome to this portfolio platform."
);
path($mayor_dir, 'about.md')->spew(
	"---\ntitle: About\n---\n\nAbout page content."
);
path($mayor_dir, 'notes.txt')->spew("Plain text notes.");

my $t = Test::Mojo->new('Bliptown');

# Bliptown startup resets the health file; populate it for health check tests
path($env->{health})->spew('1');

# Helper to add Host header to all requests in this integration suite
my $host_header = { Host => 'localhost' };

subtest 'GET / returns 200 with page content' => sub {
	$t->get_ok('/' => $host_header)
		->status_is(200)
		->content_like(qr/portfolio platform/i, 'page body content present');
};

subtest 'GET /about returns 200 with about page' => sub {
	$t->get_ok('/about' => $host_header)
		->status_is(200)
		->content_like(qr/About page content/i);
};

subtest 'GET /nonexistent returns 404' => sub {
	$t->get_ok('/nonexistent-page-that-does-not-exist' => $host_header)
		->status_is(404);
};

subtest 'GET /login with no credentials returns 401 with login form' => sub {
	$t->get_ok('/login' => $host_header)
		->status_is(401)
		->content_like(qr/username/i, 'response contains username field');
};

subtest 'GET /logout redirects' => sub {
	$t->get_ok('/logout' => $host_header)
		->status_is(302);
};

subtest 'GET /health returns 200 with JSON' => sub {
	$t->get_ok('/health' => $host_header)
		->status_is(200)
		->json_has('/BliptownDatabaseOK', 'DB OK field present');
};

subtest 'GET /track/:rand returns empty body' => sub {
	$t->get_ok('/track/abc1234' => { %$host_header, Referer => '' })
		->status_is(200)
		->content_is('');
};

subtest 'GET /raw/about returns raw markdown' => sub {
	$t->get_ok('/raw/about' => $host_header)
		->status_is(200)
		->content_like(qr/About page content/);
};

subtest 'GET /raw/notes.txt returns plain text content' => sub {
	$t->get_ok('/raw/notes.txt' => $host_header)
		->status_is(200)
		->content_like(qr/Plain text notes/);
};

subtest 'GET /raw/nonexistent returns 404' => sub {
	$t->get_ok('/raw/nonexistent-file' => $host_header)
		->status_is(404);
};

# Test protected routes (should return 403 without login)
subtest 'GET /edit/about returns 403 without login' => sub {
	$t->get_ok('/edit/about' => $host_header)
		->status_is(403)
		->content_like(qr/Forbidden|login required/i);
};

subtest 'GET /new/page returns 403 without login' => sub {
	$t->get_ok('/new/newpage' => $host_header)
		->status_is(403);
};

subtest 'GET /files returns 403 without login' => sub {
	$t->get_ok('/files' => $host_header)
		->status_is(403);
};

subtest 'GET /settings returns 403 without login' => sub {
	$t->get_ok('/settings' => $host_header)
		->status_is(403);
};

subtest 'GET /snapshots returns 403 without login' => sub {
	$t->get_ok('/snapshots' => $host_header)
		->status_is(403);
};

# Test login flow
subtest 'POST /login with invalid credentials returns 401' => sub {
	$t->post_ok('/login' => $host_header => form => {
		username => 'mayor',
		password => 'wrongpassword',
		totp     => '000000',
	})->status_is(401)
		->content_like(qr/Unauthorized|incorrect/i);
};

subtest 'POST /login with missing user returns 401' => sub {
	$t->post_ok('/login' => $host_header => form => {
		username => 'nosuchuser',
		password => 'anypassword',
		totp     => '000000',
	})->status_is(401);
};

# Test demo user login (TOTP not required)
subtest 'demo user login without TOTP' => sub {
	# Create demo user via model
	my $sql  = BliptownTest::create_sqlite($env->{db_file});
	use Bliptown::Model::TOTP;
	use Bliptown::Model::User;
	my $user_model = Bliptown::Model::User->new(
		sqlite => $sql,
		totp   => Bliptown::Model::TOTP->new,
	);
	$user_model->create_user({
		username => 'demo',
		email    => 'demo@example.com',
		password => 'demopassword',
	});
	path($env->{user_home}, 'demo')->make_path;

	# demo user authenticates without a TOTP
	my $result = $user_model->authenticate_user({
		username => 'demo',
		password => 'demopassword',
		totp     => '',
	});
	ok $result, 'demo user authenticates successfully without TOTP';
};

done_testing;
