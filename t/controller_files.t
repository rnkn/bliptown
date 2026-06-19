use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;

use_ok qw(Bliptown::Controller::Files);

my $t = Test::Mojo->new('Bliptown');
my $log = Mojo::Log->new;
my $debug_messages = $log->capture('debug');
my $app = $t->app;
$app->log($log);

$app->helper(
	ipc => sub {
		return FakeIPC->new;
	}
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

subtest 'format_human_size' => sub {
	my $fhs = \&Bliptown::Controller::Files::format_human_size;

    my $one_mb = 1024 * 1024;
    my $one_gb = 1024 * 1024 * 1024;
    my $one_tb = 1024 * 1024 * 1024 * 1024;

    is $fhs->(0),       '0B',     'zero bytes';
    is $fhs->(1),       '1B',     'one byte';
    is $fhs->(512),     '512B',   'sub-kilobyte';
    is $fhs->(1023),    '1023B',  'just below 1K';
    is $fhs->(1024),    '1.00K',  'exactly 1K';
    is $fhs->(1536),    '1.50K',  '1.5K';
    is $fhs->(2048),    '2.00K',  '2K';
    is $fhs->($one_mb), '1.00M',  '1M';
    is $fhs->($one_gb), '1.00G',  '1G';
    is $fhs->($one_tb), '1.00T',  '1T';
};

$t->post_ok('/files' => { Host => $user_domain } => form => {
	action		=> 'new_directory',
	name		=> 'fakedir',
})->status_is(302);

like $debug_messages, qr{Created directory: $user_dir/fakedir};

$user_dir->child('foo.md')->touch;
$user_dir->child('bar.md')->touch;
$user_dir->child('subdir')->make_path;
$user_dir->child('subdir/baz.md')->touch;

$t->get_ok('/files' => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_like(qr{<a href="/bar">bar.md</a>})
	->content_like(qr{<a href="/files/subdir">subdir</a>});

$t->get_ok('/files/subdir' => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/subdir/baz">baz.md</a>});

$t->get_ok(Mojo::URL->new('/files')->query(search => 'foo') => { Host => $user_domain })->status_is(200)
	->content_like(qr{<a href="/foo">foo.md</a>})
	->content_unlike(qr{<a href="/bar">bar.md</a>});

$t->get_ok('/delete/foo.md' => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Deleted: $user_dir/foo.md};

$t->get_ok(Mojo::URL->new('/files')->query(search => 'ba', delete => 1) => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Deleted: $user_dir/bar.md};
like $debug_messages, qr{Deleted: $user_dir/subdir/baz.md};

$t->get_ok(Mojo::URL->new('/rename/foo.md')->query(name => 'bar.md') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_dir/foo.md -> $user_dir/bar.md};

$t->get_ok(Mojo::URL->new('/files')->query(search => 'ba', replace => 'qu') => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Renamed file: $user_dir/bar.md -> $user_dir/qur.md};
like $debug_messages, qr{Renamed file: $user_dir/subdir/baz.md -> $user_dir/subdir/quz.md};

$t->get_ok('/backup/foo.md' => { Host => $user_domain })->status_is(302);
like $debug_messages, qr{Created backup file: $user_dir/foo.md~};

done_testing;
