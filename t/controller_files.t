use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;
use Test::Mojo;

use BliptownTest qw(create_test create_app CSRF_TOKEN);
use FakeIPC;

use_ok qw(Bliptown::Controller::Files);

my $t				= create_test;
my $app				= create_app;
my $debug_messages	= $app->log->capture('debug');

$ENV{BLIPTOWN_DATA_HOME} = tempdir;

my $username	= 'testuser';
my $user_path	= path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->make_path->realpath;
my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

$t->post_ok($app->url_for('new_directory') => { Host => $user_domain } => form => {
	dir			=> '',
	csrf_token	=> CSRF_TOKEN,
	name		=> 'fakedir',
})->status_is(302);
like $debug_messages, qr{Created directory: $user_path/fakedir};

$user_path->child('foo.md')->touch;
$user_path->child('bar.md')->touch;
$user_path->child('subdir')->make_path;
$user_path->child('subdir/baz.md')->touch;

$t->get_ok($app->url_for('list_files') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_like(qr{<a href="/bar">bar.md</a>})
	->content_like(qr{<a href="/_files/subdir">subdir</a>});

$t->get_ok($app->url_for('list_files', catchall => 'subdir') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/subdir/baz">baz.md</a>});

$t->get_ok($app->url_for('list_files')->query(search => 'foo') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_unlike(qr{<a href="/bar">bar.md</a>});

$t->post_ok($app->url_for('delete_files') => { Host => $user_domain } => form => {
	csrf_token	=> CSRF_TOKEN,
	filenames => 'foo.md',
})->status_is(302);
like $debug_messages, qr{Deleted:.*/foo\.md};

$user_path->child('foo.md')->remove;

$t->post_ok($app->url_for('rename_files') => { Host => $user_domain } => form => {
	csrf_token	=> CSRF_TOKEN,
	old => 'bar.md',
	new => 'qux.md',
})->status_is(302);
like $debug_messages, qr{Renamed file:.*/bar\.md ->.*/qux\.md};

$user_path->child('bar.md')->remove;
$user_path->child('qux.md')->touch;

$t->post_ok($app->url_for('rename_files') => { Host => $user_domain } => form => {
	csrf_token	=> CSRF_TOKEN,
	dir	=> 'subdir',
	old	=> '*ba*',
	new	=> 'quz.md',
})->status_is(302);
like $debug_messages, qr{Renamed file:.*/subdir/baz\.md ->.*/subdir/quz\.md};

$user_path->child('subdir/baz.md')->remove;
$user_path->child('subdir/quz.md')->touch;

$t->post_ok($app->url_for('delete_files') => { Host => $user_domain } => form => {
	csrf_token	=> CSRF_TOKEN,
	filenames => 'qu',
})->status_is(302);
like $debug_messages, qr{Deleted:.*/qux\.md};
like $debug_messages, qr{Deleted:.*/subdir/quz\.md};

$user_path->child('backup_test.md')->touch;

$t->post_ok($app->url_for('backup_file') => { Host => $user_domain } => form => {
	csrf_token	=> CSRF_TOKEN,
	filename => 'backup_test.md',
})->status_is(302);
like $debug_messages, qr{Created backup file:.*/backup_test\.md~};

done_testing;
