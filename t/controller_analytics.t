use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Digest::SHA qw(hmac_sha1_hex);
use Mojo::JSON qw(encode_json);
use Test::More;
use Test::Mojo;

use BliptownTest qw(create_test create_app);

use_ok qw(Bliptown::Controller::Analytics);

my $t		= create_test;
my $app		= create_app;

my $username	= 'testuser';
my $user_domain	= "$username.$ENV{BLIPTOWN_DOMAIN}";

path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;

my $ip			= '192.168.1.1';
my $ip_hash		= hmac_sha1_hex($ip, $app->secrets->[0]);
my $user_agent	= 'Bliptown/1.0';
my $referrer	= 'https://example.com/referring/page';

my $url = Mojo::URL->new;
$url->scheme('https');
$url->host($user_domain);
$url->path('/some/path');
$url->query({ foo => 'bar' });

my $tx = Mojo::Transaction::HTTP->new;
$tx->remote_address($ip);
$tx->req->headers->host($user_domain);
$tx->req->headers->referrer($url);
$tx->req->headers->user_agent($user_agent);
$tx->req->url->query({ ref => $referrer });

my $c = Bliptown::Controller::Analytics->new(app => $app);
$c->tx($tx);

subtest 'get_data' => sub {
	my $data = $c->get_data;

	is $data->[0], $ip_hash, 'get_data returns hashed IP';
	is $data->[1], $url->host, 'get_data returns host';
	is $data->[2], $url->path_query, 'get_data returns path and query';
	is $data->[3], $referrer, 'get_data returns referrer';
	is $data->[4], $user_agent, 'get_data returns user agent';
	is $data->[6], $user_domain, 'get_data returns vhost';
};

my $visitor_log = FakeVisitorLog->new;
$app->helper(visitor_log => sub { $visitor_log });

$t->post_ok($app->url_for('track_visit')->query(ref => $referrer) => { Host => $user_domain, Referer => $url->to_string })
	->status_is(200)
	->content_is('');

subtest 'track_visit' => sub {
	my $visits = $visitor_log->visits;
	is scalar @$visits, 1, 'track_visit logs visit';

	my $visit = $visits->[0];
	is $visit->[0], $username, 'track_visit logs username';
	like $visit->[1], qr/^[0-9a-f]{40}$/, 'track_visit logs hashed IP';
	is $visit->[2], $url->host, 'track_visit logs host';
	is $visit->[3], $url->path_query, 'track_visit logs path and query';
	is $visit->[4], $referrer, 'track_visit logs referrer';
	is $visit->[7], $user_domain, 'track_visit logs vhost';

	$t->post_ok($app->url_for('track_visit') => { Host => "unresolvable.example.com" })
		->status_is(404);
};

subtest 'render_stats' => sub {
	$t->get_ok($app->url_for('render_stats') => { Host => $user_domain })
		->status_is(403);

	$app->hook(
		before_dispatch => sub {
			my $c = shift;
			$c->session(username => $username);
			return 1;
		}
	);

	$t->post_ok($app->url_for('track_visit') => { Host => $user_domain })
		->status_is(200)
		->content_is('');
	is scalar @{$visitor_log->visits}, 1, 'track_visit does not log a self visit';

	$t->get_ok($app->url_for('render_stats') => { Host => $user_domain })
		->status_is(200)
		->text_is('h1', 'Stats')
		->content_like(qr/No stats yet/);

	my $stats = {
		date => [
			{ key => '2026-09-28 Mon', hits => 12, visitors => 3 },
			{ key => '2026-09-27 Sun', hits => 4, visitors => 1 },
		],
		country => [
			{ key => 'Germany', hits => 16, visitors => 4 },
		],
	};

	path($ENV{BLIPTOWN_DATA_HOME}, 'stats')->make_path;
	path($ENV{BLIPTOWN_DATA_HOME}, 'stats', "$username.json")->spurt(encode_json($stats));

	$t->get_ok($app->url_for('render_stats') => { Host => $user_domain })
		->status_is(200)
		->element_exists('progress[max="12"][value="12"]')
		->element_exists('progress[max="12"][value="4"]')
		->element_exists('progress[max="16"][value="16"]');
};

done_testing;
