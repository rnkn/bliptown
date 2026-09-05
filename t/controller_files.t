use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;

use_ok qw(Bliptown::Controller::Files);

my $t				= Test::Mojo->new('Bliptown');
my $app				= $t->app;
my $log				= Mojo::Log->new;
my $debug_messages	= $log->capture('debug');

$app->log($log);

my $ipc = FakeIPC->new;

$app->helper(
	ipc => sub { return $ipc }
);

$ENV{BLIPTOWN_DATA_HOME} = tempdir;

my $username	= 'testuser';
my $user_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

$t->post_ok('/files' => { Host => $user_domain } => form => {
	action		=> 'new_directory',
	name		=> 'fakedir',
})->status_is(302);

like $debug_messages, qr{Created directory: $user_home/fakedir};

$user_home->child('foo.md')->touch;
$user_home->child('bar.md')->touch;
$user_home->child('subdir')->make_path;
$user_home->child('subdir/baz.md')->touch;

$t->get_ok($app->url_for('list_files') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_like(qr{<a href="/bar">bar.md</a>})
	->content_like(qr{<a href="/files/subdir">subdir</a>});

$t->get_ok($app->url_for('list_files', catchall => 'subdir') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/subdir/baz">baz.md</a>});

$t->get_ok($app->url_for('list_files')->query(search => 'foo') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_unlike(qr{<a href="/bar">bar.md</a>});

$t->get_ok($app->url_for('delete_file', catchall => 'foo.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Deleted: $user_home/foo.md};

$t->get_ok($app->url_for('list_files')->query(search => 'ba', delete => 1) => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Deleted: $user_home/bar.md};
like $debug_messages, qr{Deleted: $user_home/subdir/baz.md};

$t->get_ok($app->url_for('rename_file', catchall => 'foo.md')->query(name => 'bar.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_home/foo.md -> $user_home/bar.md};

$t->get_ok($app->url_for('list_files')->query(search => 'ba', replace => 'qu') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_home/bar.md -> $user_home/qur.md};
like $debug_messages, qr{Renamed file: $user_home/subdir/baz.md -> $user_home/subdir/quz.md};

$t->get_ok($app->url_for('backup_file', catchall => 'foo.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Created backup file: $user_home/foo.md~};

done_testing;
