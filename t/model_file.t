use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use_ok qw(Bliptown::Model::File);

my $file = Bliptown::Model::File->new;

my $tempbase	= tempdir;
my $username	= 'testuser';
my $filename	= 'foo.md';
my $user_dir	= $tempbase->child('users')->child($username)->make_path;

$user_dir->child($filename)->spew('Hello world!');

subtest 'read_file' => sub {
	my $f = path($user_dir, $filename)->to_abs->to_string;
	my $content = $file->read_file({ file =>  $f });
	is $content->{chars}, 'Hello world!', 'read_file reads file chars';
};

subtest 'purge_cdn_file' => sub {
	my $url = 'https://example.com/dog.jpg';
	my $res = $file->purge_cdn_file({ url => $url });
	ok $res = 404;
};

done_testing;
