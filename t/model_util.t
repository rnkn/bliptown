use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::Util);

my $util = Bliptown::Model::Util->new;

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

subtest 'process_prettydate with DAY MONTH YEAR format' => sub {
	my $result = $util->process_prettydate('2999-12-31');
	like $result, qr/31/, 'process_prettydate returns day';
	like $result, qr/December/, 'process_prettydate returns month';
	like $result, qr/2999/, 'process_prettydate returns year';
};

subtest 'process_prettydate ISO format (YYY-MM-DD)' => sub {
	my $result = $util->process_prettydate('2999-12-31', 4);
	is $result, '2999-12-31', 'process_prettydate returns YYYY-MM-DD';
};

subtest 'file_to_slug strip' => sub {
	my $root = '/path/to/file';
	my $filename = "$root/about.md";
	my $slug = $util->file_to_slug($filename, { root => $root });
	is $slug, '/about', 'file_to_slug returns slug';
};

subtest 'glob_path absolute pattern' => sub {
	my $root = tempdir(DIR => THIS_DIR);

	my $a = $root->child('a.md')->touch->to_abs->to_string;
	my $b = $root->child('b.md')->touch->to_abs->to_string;
	my $c = $root->child('c.md')->touch->to_abs->to_string;
	my $ignore = $root->child('ignored.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('/*.md', { root => $root->to_abs->to_string, filename => $ignore });
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'glob_path returns correct files';
};

subtest 'glob_path relative pattern' => sub {
	my $root = tempdir(DIR => THIS_DIR);

	my $a = $root->child('a.md')->touch->to_abs->to_string;
	my $b = $root->child('b.md')->touch->to_abs->to_string;
	my $c = $root->child('c.md')->touch->to_abs->to_string;
	my $ignore = $root->child('ignored.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('*.md', { filename => $ignore });
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'glob_path returns correct files';
};

done_testing;
