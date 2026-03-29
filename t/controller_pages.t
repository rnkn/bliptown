use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use File::Temp qw(tempdir);
use Mojo::File qw(path);

BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use Bliptown::Controller::Pages;

my $process_redirects = \&Bliptown::Controller::Pages::process_redirects;
my $postprocess_skel  = \&Bliptown::Controller::Pages::postprocess_skel;

my $tmpdir = tempdir(CLEANUP => 1);

# --- process_redirects ---

subtest 'process_redirects returns URL for matching slug' => sub {
	my $file = path($tmpdir, '_redirects.txt');
	$file->spew("/old: https://example.com/new\n");
	my $url = $process_redirects->($file, '/old');
	is $url, 'https://example.com/new', 'redirect URL returned for known path';
};

subtest 'process_redirects returns undef for no match' => sub {
	my $file = path($tmpdir, '_redirects2.txt');
	$file->spew("/other: https://example.com/other\n");
	my $url = $process_redirects->($file, '/unknown');
	ok !defined $url, 'undef returned for unknown path';
};

subtest 'process_redirects handles slug without leading slash' => sub {
	my $file = path($tmpdir, '_redirects3.txt');
	$file->spew("/about: https://example.com/about-us\n");
	my $url = $process_redirects->($file, 'about');
	is $url, 'https://example.com/about-us', 'slug without slash also matched';
};

subtest 'process_redirects handles trailing slash in slug' => sub {
	my $file = path($tmpdir, '_redirects4.txt');
	$file->spew("/docs: https://docs.example.com\n");
	my $url = $process_redirects->($file, '/docs/');
	is $url, 'https://docs.example.com', 'trailing slash stripped so entry is matched';
};

# --- postprocess_skel ---

subtest 'postprocess_skel adds selected class to matching link' => sub {
	my $html = '<nav><ul><li><a href="/about">About</a></li></ul></nav>';
	my $result = $postprocess_skel->($html, '/about');
	like $result, qr{class="selected"}, 'selected class added to matching link';
	like $result, qr{href="/about"}, 'link href preserved';
};

subtest 'postprocess_skel does not modify non-matching links' => sub {
	my $html = '<nav><a href="/home">Home</a><a href="/about">About</a></nav>';
	my $result = $postprocess_skel->($html, '/home');
	like $result, qr{class="selected"[^>]*href="/home"|href="/home"[^>]*class="selected"}, 'home link gets selected';
	unlike $result, qr{href="/about"[^>]*selected}, 'about link not selected';
};

subtest 'postprocess_skel opens parent details element' => sub {
	my $html = '<details><summary>Section</summary><a href="/docs">Docs</a></details>';
	my $result = $postprocess_skel->($html, '/docs');
	like $result, qr{<details\s+open>}, 'parent details opened';
};

subtest 'postprocess_skel handles slug without leading slash' => sub {
	my $html = '<a href="/page">Page</a>';
	my $result = $postprocess_skel->($html, 'page');
	like $result, qr{class="selected"}, 'works without leading slash on slug';
};

done_testing;
