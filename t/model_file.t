use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;

my $file = Bliptown::Model::File->new;

my $tempbase	= tempdir;
my $username	= 'testuser';
my $filename	= 'foo.md';
my $user_path	= $tempbase->child('users')->child($username)->make_path;

$user_path->child($filename)->spew('Hello world!');

subtest 'read_file' => sub {
	my $path = path($user_path, $filename)->to_abs;
	my $content = $file->read_file({ filename =>  $path->to_string });
	is $content->{chars}, 'Hello world!', 'read_file reads file chars';
};

subtest 'purge_cdn_file' => sub {
	my $path = path($user_path, $filename)->to_abs;
	my $res = $file->purge_cdn_file({ filename => $path->to_string });
	ok $res = 404;
};

done_testing;
