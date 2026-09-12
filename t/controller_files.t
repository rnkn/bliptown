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
$ENV{BLIPTOWN_DOMAIN} = 'example.com';

my $username	= 'testuser';
my $user_home	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path;
my $user_domain = "$username.example.com";

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

# Test new_directory
$t->post_ok($app->url_for('new_directory') => { Host => $user_domain } => form => {
	dir		=> '',
	name		=> 'fakedir',
})->status_is(302);

like $debug_messages, qr{Created directory: $user_home//?fakedir};

# Create test files
$user_home->child('foo.md')->touch;
$user_home->child('bar.md')->touch;
$user_home->child('subdir')->make_path;
$user_home->child('subdir/baz.md')->touch;

# Test list_files
$t->get_ok($app->url_for('list_files') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_like(qr{<a href="/bar">bar.md</a>})
	->content_like(qr{<a href="/_files/subdir">subdir</a>});

$t->get_ok($app->url_for('list_files', catchall => 'subdir') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/subdir/baz">baz.md</a>});

$t->get_ok($app->url_for('list_files')->query(search => 'foo') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_unlike(qr{<a href="/bar">bar.md</a>});

# Test delete_files with filename
$t->post_ok($app->url_for('delete_files') => { Host => $user_domain } => form => {
	filename => 'foo.md',
})->status_is(302);
like $debug_messages, qr{Deleted:.*/foo\.md};

# Remove the file from filesystem to match FakeIPC behavior
$user_home->child('foo.md')->remove;

# Test rename_files with filename and new_filename
$t->post_ok($app->url_for('rename_files') => { Host => $user_domain } => form => {
	filename => 'bar.md',
	new_filename => 'qux.md',
})->status_is(302);
like $debug_messages, qr{Renamed file:.*/bar\.md ->.*/qux\.md};

# Manually rename the file to match the expected state
$user_home->child('bar.md')->remove;
$user_home->child('qux.md')->touch;

# Test rename_files with search/replace
$t->post_ok($app->url_for('rename_files') => { Host => $user_domain } => form => {
	search => 'ba',
	replace => 'qu',
})->status_is(302);
like $debug_messages, qr{Renamed file:.*/subdir/baz\.md ->.*/subdir/quz\.md};

# Manually rename the file
$user_home->child('subdir/baz.md')->remove;
$user_home->child('subdir/quz.md')->touch;

# Test delete_files with search
$t->post_ok($app->url_for('delete_files') => { Host => $user_domain } => form => {
	search => 'qu',
})->status_is(302);
like $debug_messages, qr{Deleted:.*/qux\.md};
like $debug_messages, qr{Deleted:.*/subdir/quz\.md};

# Create a fresh file for backup test
$user_home->child('backup_test.md')->touch;

# Test backup_file
$t->post_ok($app->url_for('backup_file') => { Host => $user_domain } => form => {
	filename => 'backup_test.md',
})->status_is(302);
like $debug_messages, qr{Created backup file:.*/backup_test\.md~};

done_testing;