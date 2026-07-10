use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;

use_ok qw(Bliptown::Controller::Snapshots);

my $t			= Test::Mojo->new('Bliptown');
my $app			= $t->app;
my $ipc			= FakeIPC->new;
my $username	= 'testuser';
my $user_domain	= "$username.$ENV{BLIPTOWN_DOMAIN}";

$app->helper(
	ipc => sub { return $ipc }
);

$app->config->{user_home} = tempdir;

path($app->config->{user_home}, $username)->make_path;

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

subtest 'system git' => sub {
	my $git_version = system('git -v') == 0 ? 1 : 0;
	ok $git_version, 'system has git';
};

my $hash = 'df78309';

$t->get_ok($app->url_for('list_snapshots') => { Host => $user_domain })->status_is(200)
	->text_is('nav header h1', 'Snapshots', 'list_snapshots renders title')
	->element_exists('main#snapshots div#list', 'list_snapshots renders list element')
	->text_is('details#clone pre', "git clone $username\@blip.town:site", 'list_snapshots returns git clone URL')
	->text_is('div#list details summary span#commit-hash code', $hash, 'list_snapshots returns git commit hash')
	->text_is('div#list details summary span#commit-date', '2999-06-08 11:03 +0000', 'list_snapshots returns git commit date')
	->text_is('div#list details pre#commit-body', 'A  blog/2999-06-08.md', 'list_snapshots returns git commit body');

$t->get_ok($app->url_for('take_snapshot') => { Host => $user_domain })->status_is(302);

subtest 'take_snapshot' => sub {
	is $t->tx->res->headers->location, $app->url_for('list_snapshots'),
		'take_snapshot redirects to snapshots URL';
};

$t->get_ok($app->url_for('download_snapshot', hash => $hash) => { Host => $user_domain })->status_is(200);

subtest 'download_snapshot' => sub {
	is $t->tx->res->headers->content_type, 'application/gzip',
		'download_snapshot returns correct Content-Type';
	is $t->tx->res->headers->content_disposition, "attachment; filename=${user_domain}-${hash}.tar.gz",
		'download_snapshot returns correct Content-Disposition';
};

$t->get_ok($app->url_for('download_snapshot', hash => 'invalid') => { Host => $user_domain })->status_is(500);

$t->get_ok($app->url_for('restore_snapshot', hash => $hash) => { Host => $user_domain })->status_is(302);

subtest 'restore_snapshot' => sub {
	is $t->tx->res->headers->location, $app->url_for('list_files')->query(search => "snapshots/$hash"),
		'restore_snapshot redirects to search URL';
};

$t->get_ok($app->url_for('restore_snapshot', hash => 'invalid') => { Host => $user_domain })->status_is(500);

$t->get_ok($app->url_for('render_diff', hash => $hash) => { Host => $user_domain })->status_is(200)
	->text_is('nav header h1', "Snapshot $hash", 'render_diff renders title')
	->element_exists('main#diff pre.diff', 'render_diff renders pre element')
	->text_like('main#diff pre.diff span.meta', qr/commit $hash/, 'render_diff retrieves commit');

$t->get_ok($app->url_for('render_diff', hash => 'invalid') => { Host => $user_domain })->status_is(500);

done_testing;
