use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Digest::SHA qw(hmac_sha1_hex);
use Test::More;
use Test::Mojo;

use_ok qw(Bliptown::Controller::Analytics);

my $t						= Test::Mojo->new('Bliptown');
my $app						= $t->app;
my $username				= 'testuser';
my $user_domain				= "$username.$ENV{BLIPTOWN_DOMAIN}";
$app->config->{user_home}	= tempdir;
$app->config->{log_home}	= tempdir;

path($app->config->{user_home}, $username)->make_path;

my $logdir	= path($app->config->{log_home}, 'users', $username)->make_path;
my $logpath = path($logdir, 'access.log')->touch->chmod(0600);

my $url = Mojo::URL->new;
$url->scheme('https');
$url->host($user_domain);
$url->path('/some/path');
$url->query({ foo => 'bar' });

my $ip			= '192.168.1.1';
my $ip_hash		= hmac_sha1_hex($ip, $app->secrets->[0]);
my $user_agent	= 'Bliptown/1.0';
my $referrer	= 'https://example.com/referring/page';

my $tx = Mojo::Transaction::HTTP->new;
$tx->remote_address($ip);
$tx->req->headers->referrer($url);
$tx->req->headers->user_agent($user_agent);
$tx->req->url->query({ ref => $referrer });
$tx->req->headers->host($user_domain);

my $time = time;
my $c = Bliptown::Controller::Analytics->new(app => $app);
$c->tx($tx);

my $data = $c->get_data;

subtest 'get_data' => sub {
	is $data->[0],	$ip_hash,			'get_data returns hashed IP';
	is $data->[1],	$url->host,			'get_data returns host';
	is $data->[2],	$url->path_query,	'get_data returns path and query';
	is $data->[3],	$referrer,			'get_data returns referrer';
	is $data->[4],	$user_agent,			'get_data returns user agent';
	is $data->[6],	$user_domain,		'get_data returns vhost';
};

$c->log_data($username, $data);

subtest 'log_data' => sub {
	my @logs = $logpath->slurp;
	my $log = $logs[0];
	chomp $log;
	my @vals = split /\t/, $log;
	is $vals[0],	$time,				'log_data logs time';
	is $vals[1],	$ip_hash,			'log_data logs hashed IP';
	is $vals[2],	$url->host,			'log_data logs host';
	is $vals[3],	$url->path_query,	'log_data logs path and query';
	is $vals[4],	$referrer,			'log_data logs referrer';
	is $vals[5],	$user_agent,		'log_data logs user agent';
	is $vals[7],	$user_domain,		'log_data logs vhost';
};

done_testing;
