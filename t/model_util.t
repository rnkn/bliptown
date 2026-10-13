use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::Util);

my $user_path = tempdir;

my $util = Bliptown::Model::Util->new(
	user_path => $user_path,
);

subtest 'format_human_size' => sub {
    my $one_mb = 1024 * 1024;
    my $one_gb = 1024 * 1024 * 1024;
    my $one_tb = 1024 * 1024 * 1024 * 1024;

    is $util->format_human_size(0),			'0B',		'zero bytes';
    is $util->format_human_size(1),			'1B',		'one byte';
    is $util->format_human_size(512),		'512B',		'sub-kilobyte';
    is $util->format_human_size(1023),		'1023B',	'just below 1K';
    is $util->format_human_size(1024),		'1.00K',	'exactly 1K';
    is $util->format_human_size(1536),		'1.50K',	'1.5K';
    is $util->format_human_size(2048),		'2.00K',	'2K';
    is $util->format_human_size($one_mb),	'1.00M',	'1M';
    is $util->format_human_size($one_gb),	'1.00G',	'1G';
    is $util->format_human_size($one_tb),	'1.00T',	'1T';
};

subtest 'ipv6_equal' => sub {
	my $ipv6_1	= '2001:0db8:0000:0000:0000:0000:0000:0001';
	my $ipv6_2	= '2001:db8::1';
	my $ipv6_3	= '2001:db8::2';
	ok $util->ipv6_equal($ipv6_1, $ipv6_2), 'ipv6_equal validates compressed IPv6 address';
	ok ! $util->ipv6_equal($ipv6_1, 'invalid'), 'ipv6_equal invalid IPv6 address';
	ok ! $util->ipv6_equal($ipv6_1, $ipv6_3), 'ipv6_equal different IPv6 address';
};

subtest 'create_stripe_url' => sub {
	my $path = 'test/path';
	my $emptypath;
	my $url = $util->create_stripe_url($path);
	my $userinfo = $url->userinfo;
	is $url, "https://api.stripe.com/test/path", 'create_stripe_url creates URL';
	is $userinfo, $ENV{BLIPTOWN_STRIPE_API_KEY} . ':', 'create_stripe_url returns correct userinfo';
	ok ! $util->create_stripe_url($emptypath), 'create_stripe_url fails with empty path';
};

subtest 'split_frontmatter valid frontmatter' => sub {
	my $content = <<'EOF';
---
title: Test
---
Hello world!
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok defined $yaml, 'split_frontmatter extracts YAML';
	like $yaml, qr/title: Test/, 'split_frontmatter parses title';
	is $text, "Hello world!\n", 'split_frontmatter returns body text';
};

subtest 'split_frontmatter no frontmatter' => sub {
	my $content = <<'EOF';
Just plain content
without YAML frontmatter.
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok !defined $yaml, 'split_frontmatter omits YAML';
	is $text, $content, 'split_frontmatter returns body text';
};

subtest 'split_frontmatter empty frontmatter' => sub {
	my $content = <<'EOF';
---
---
Hello world!
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok defined $yaml, 'split_frontmatter extracts empty YAML';
	is $text, "Hello world!\n", 'split_frontmatter returns body text';
};

subtest 'filename_to_slug strip' => sub {
	my $filename = $user_path->child('about.md');
	my $slug = $util->filename_to_slug($filename);
	is $slug, '/about', 'filename_to_slug returns slug';
};

subtest 'glob_path absolute pattern' => sub {
	my $a = $user_path->child('a.md')->touch->to_abs->to_string;
	my $b = $user_path->child('b.md')->touch->to_abs->to_string;
	my $c = $user_path->child('c.md')->touch->to_abs->to_string;
	my $ignore = $user_path->child('ignored.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('/*.md', $ignore);
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'glob_path returns correct files';
};

subtest 'glob_path relative pattern' => sub {
	my $a = $user_path->child('a.md')->touch->to_abs->to_string;
	my $b = $user_path->child('b.md')->touch->to_abs->to_string;
	my $c = $user_path->child('c.md')->touch->to_abs->to_string;
	my $ignore = $user_path->child('ignored.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('*.md', $ignore);
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'glob_path returns correct files';
};

subtest 'create_bliptown_url' => sub {
	local $ENV{BLIPTOWN_SCHEME}		= 'https';
	local $ENV{BLIPTOWN_PORT}		= '';
	local $ENV{BLIPTOWN_DOMAIN}		= 'blip.town';

	my $url = $util->create_bliptown_url({
		path		=> '/_auth',
		token		=> 'abc123',
		redirect	=> '/',
	});
	is $url->scheme, 'https', 'create_bliptown_url uses BLIPTOWN_SCHEME';
	is $url->host, 'blip.town', 'create_bliptown_url falls back to BLIPTOWN_DOMAIN';
	is $url->path, '/_auth', 'create_bliptown_url sets path';
	is $url->query->param('token'), 'abc123', 'create_bliptown_url sets token query';
	is $url->query->param('back_to'), '/', 'create_bliptown_url sets back_to query';
};

subtest 'create_bliptown_url with host and port' => sub {
	local $ENV{BLIPTOWN_SCHEME}		= 'http';
	local $ENV{BLIPTOWN_PORT}		= '3000';
	local $ENV{BLIPTOWN_DOMAIN}		= 'blip.town';

	my $url = $util->create_bliptown_url({
		host		=> 'mayor.blip.town',
		path		=> '/_logout',
		redirect	=> '/page',
	});
	is $url->scheme, 'http', 'create_bliptown_url uses custom scheme';
	is $url->host, 'mayor.blip.town', 'create_bliptown_url uses explicit host';
	is $url->port, '3000', 'create_bliptown_url sets port from env';
	is $url->path, '/_logout', 'create_bliptown_url sets path';
	is $url->query->param('back_to'), '/page', 'create_bliptown_url sets redirect';
	ok !defined $url->query->param('token'), 'create_bliptown_url omits token when undef';
};

subtest 'create_bliptown_url defaults path and query' => sub {
	local $ENV{BLIPTOWN_SCHEME}		= 'https';
	local $ENV{BLIPTOWN_PORT}		= '';
	local $ENV{BLIPTOWN_DOMAIN}		= 'blip.town';

	my $url = $util->create_bliptown_url({});
	is $url->scheme, 'https', 'create_bliptown_url uses scheme';
	is $url->host, 'blip.town', 'create_bliptown_url defaults host';
	is $url->path, '/', 'create_bliptown_url defaults path';
	ok !defined $url->query->param('token'), 'create_bliptown_url omits token by default';
	ok !defined $url->query->param('back_to'), 'create_bliptown_url omits back_to by default';
};

subtest 'read_file_line' => sub {
	my $file = $user_path->child('_domain.txt');
	$file->spew("alice.example.com\nsecond line\n");
	is $util->read_file_line($file), 'alice.example.com',
		'read_file_line returns first line chomped';
};

subtest 'read_file_line single line no newline' => sub {
	my $file = $user_path->child('_title.txt');
	$file->spew('My Site');
	is $util->read_file_line($file), 'My Site',
		'read_file_line reads line without trailing newline';
};

done_testing;
