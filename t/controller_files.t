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

my $tempbase	= tempdir;
my $user_home	= $tempbase->child('users')->make_path;
my $username	= 'testuser';

$app->config->{user_home} = $user_home;

my $user_dir = $user_home->child($username)->make_path;
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

like $debug_messages, qr{Created directory: $user_dir/fakedir};

$user_dir->child('foo.md')->touch;
$user_dir->child('bar.md')->touch;
$user_dir->child('subdir')->make_path;
$user_dir->child('subdir/baz.md')->touch;

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
like $debug_messages, qr{Deleted: $user_dir/foo.md};

$t->get_ok($app->url_for('list_files')->query(search => 'ba', delete => 1) => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Deleted: $user_dir/bar.md};
like $debug_messages, qr{Deleted: $user_dir/subdir/baz.md};

$t->get_ok($app->url_for('rename_file', catchall => 'foo.md')->query(name => 'bar.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_dir/foo.md -> $user_dir/bar.md};

$t->get_ok($app->url_for('list_files')->query(search => 'ba', replace => 'qu') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_dir/bar.md -> $user_dir/qur.md};
like $debug_messages, qr{Renamed file: $user_dir/subdir/baz.md -> $user_dir/subdir/quz.md};

$t->get_ok($app->url_for('backup_file', catchall => 'foo.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Created backup file: $user_dir/foo.md~};

done_testing;
