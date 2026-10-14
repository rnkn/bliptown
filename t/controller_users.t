use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;
use Test::Mojo;
use Mojo::URL;

use BliptownTest qw(create_test create_app);

use_ok qw(Bliptown::Controller::Users);

my $t		= create_test;
my $app		= create_app;

$ENV{BLIPTOWN_DATA_HOME} = tempdir;
$ENV{BLIPTOWN_DEMO_USER} = 'demo';

subtest 'user_login renders message' => sub {
	$t->get_ok($app->url_for('user_login') => { Host => $ENV{BLIPTOWN_DOMAIN} })
		->status_is(200)
		->text_like('main p', qr/Check your email for a login link/);
};

$app->email->{sent} = [];

$t->post_ok($app->url_for('generate_login') => { Host => $ENV{BLIPTOWN_DOMAIN} } => form => { username => 'testuser' })
	->status_is(302);

subtest 'generate_login' => sub {
	is $t->tx->res->headers->location, $app->url_for('user_login'), 'generate_login redirects to user_login';
	is $app->email->{sent}[0]{username}, 'testuser', 'send_magic_link received the username';
};

my $username = 'alice';

my $tk = $app->token->create_login_token({
	username => $username,
});

$t->get_ok($app->url_for('user_auth')->query(token => $tk) => { Host => $ENV{BLIPTOWN_DOMAIN} })
	->status_is(302);

subtest 'user_auth top-level domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, "$username.$ENV{BLIPTOWN_DOMAIN}", 'user_auth redirects to user subdomain with valid token';
	ok $t->tx->res->cookie('bliptown'), 'user_auth sets a session cookie';
};

$t->get_ok($app->url_for('user_auth')->query(token => $tk) => { Host => "$username.$ENV{BLIPTOWN_DOMAIN}" })
	->status_is(302);

subtest 'user_auth user subdomain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	ok $t->tx->res->cookie('bliptown'), 'user_auth sets a session cookie';
	ok !defined $app->token->read_login_token({ token => $tk }), 'user_auth deletes used token';
};

$t->post_ok($app->url_for('generate_logout') => { Host => "$username.$ENV{BLIPTOWN_DOMAIN}" })
	->status_is(302);

subtest 'generate_logout subdomain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, "$username.$ENV{BLIPTOWN_DOMAIN}", 'generate_logout subdomain redirects to user subdomain';
	is $url->path, $app->url_for('user_logout'), 'generate_logout redirects to user_logout';
};

$t->get_ok($app->url_for('user_logout') => { Host => "$username.$ENV{BLIPTOWN_DOMAIN}" })
	->status_is(302);

subtest 'user_logout subdomain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, $ENV{BLIPTOWN_DOMAIN}, 'user_logout subdomain redirects to top-level domain';
	is $url->path, $app->url_for('user_logout'), 'user_logout redirects to user_logout';
};

$t->reset_session;
$username  = 'bob';
my $custom_domain = 'mydomain.org';

my $user_home = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
$user_home->child('_domain.txt')->spew($custom_domain);
my $domain_home = path($ENV{BLIPTOWN_DATA_HOME}, 'domains')->make_path;
symlink $user_home->to_string, $domain_home->child($custom_domain)->to_string;

my $tk_custom_domain = $app->token->create_login_token({
	username => $username,
	custom_domain => $custom_domain,
});

$t->get_ok($app->url_for('user_auth')->query(token => $tk_custom_domain) => { Host => $ENV{BLIPTOWN_DOMAIN} })
	->status_is(302);

subtest 'user_auth top-level domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, "$username.$ENV{BLIPTOWN_DOMAIN}", 'user_auth top-level domain redirects to user subdomain with valid token';
	ok $t->tx->res->cookie('bliptown'), 'user_auth sets a session cookie';
};

$t->get_ok($app->url_for('user_auth')->query(token => $tk_custom_domain) => { Host => "$username.$ENV{BLIPTOWN_DOMAIN}" })
	->status_is(302);

subtest 'user_auth user subdomain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, "$custom_domain", 'user_auth user subdomain redirects to user custom domain with valid token';
	ok $t->tx->res->cookie('bliptown'), 'user_auth sets a session cookie';
};

$t->get_ok($app->url_for('user_auth')->query(token => $tk_custom_domain, back_to => '/redirect') => { Host => $custom_domain })
	->status_is(302);

subtest 'user_auth custom domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->path, '/redirect', 'user_auth redirects to back_to query parameter';
	ok $t->tx->res->cookie('bliptown'), 'user_auth sets a session cookie';
	ok !defined $app->token->read_login_token({ token => $tk_custom_domain }), 'user_auth deletes used token';
};

$t->post_ok($app->url_for('generate_logout') => { Host => $custom_domain })
	->status_is(302);

subtest 'generate_logout custom domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, $custom_domain, 'generate_logout custom domain redirects to custom domain';
	is $url->path, $app->url_for('user_logout'), 'generate_logout redirects to user_logout path';
};

$t->get_ok($app->url_for('user_logout') => { Host => $custom_domain })
	->status_is(302);

subtest 'user_logout custom domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, "$username.$ENV{BLIPTOWN_DOMAIN}", 'user_logout custom domain redirects to user subdomain';
	is $url->path, $app->url_for('user_logout'), 'user_logout redirects to user_logout';
};

$t->get_ok($app->url_for('user_logout') => { Host => "$username.$ENV{BLIPTOWN_DOMAIN}" })
	->status_is(302);

subtest 'user_logout user subdomain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->host, $ENV{BLIPTOWN_DOMAIN}, 'user_logout user subdomain redirects to top-level';
	is $url->path, $app->url_for('user_logout'), 'user_logout redirects to user_logout';
};

$t->get_ok($app->url_for('user_logout') => { Host => $ENV{BLIPTOWN_DOMAIN} })
	->status_is(302);

subtest 'user_logout top-level domain' => sub {
	my $url = Mojo::URL->new($t->tx->res->headers->location);
	is $url->path, '/', 'user_logout redirects to home';
};

$t->reset_session;

my $tk_expired = $app->token->create_login_token({
	username => $username,
});

$app->db->update('login_tokens', { expires => time - 1 }, { token => $tk_expired });

$t->get_ok($app->url_for('user_auth')->query(token => $tk_expired) => { Host => $ENV{BLIPTOWN_DOMAIN} })
	->status_is(403)
	->text_like('main p', qr/Sorry, that token is invalid or expired/);

$t->reset_session;

$t->post_ok($app->url_for('generate_login') => { Host => $ENV{BLIPTOWN_DOMAIN} } => form => {
	username	=> 'demo',
	back_to		=> '/redirect',
})->status_is(302);

subtest 'generate_login demo user' => sub {
	is $t->tx->res->headers->location, '/redirect', 'generate_login redirects demo user to back_to';
	ok $t->tx->res->cookie('bliptown'), 'generate_login sets a session cookie for demo user';
};

done_testing;
