use Mojo::Base -strict;
use File::Basename;
use constant CWD => dirname(__FILE__);
use lib CWD . '/../lib';
use Mojo::File qw(path tempdir);
use Test::More;

use Bliptown::Model::Util;

my $util = Bliptown::Model::Util->new;

subtest 'split_frontmatter with valid frontmatter' => sub {
	my $content = <<EOF;
---
title: Test
---
Hello world!
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok defined $yaml, 'YAML extracted';
	like $yaml, qr/title: Test/, 'YAML contains title';
	is $text, "Hello world!\n", 'content correct';
};

subtest 'split_frontmatter without frontmatter' => sub {
	my $content = <<EOF;
Just plain content
without YAML frontmatter.
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok !defined $yaml, 'no YAML extracted';
	is $text, $content, 'content returned';
};

subtest 'split_frontmatter with empty frontmatter block' => sub {
	my $content = <<EOF;
---
---
Hello world!
EOF
	my ($yaml, $text) = $util->split_frontmatter($content);
	ok defined $yaml, 'yaml extracted (even if empty)';
	is $text, "Hello world!\n", 'content returned';
};

subtest 'process_prettydate with DAY MONTH YEAR format' => sub {
	my $result = $util->process_prettydate('2999-12-31');
	like $result, qr/31/, 'day appears in output';
	like $result, qr/December/, 'month name appears in output';
	like $result, qr/2999/, 'year appears in output';
};

subtest 'process_prettydate with ISO format (YYY-MM-DD)' => sub {
	my $result = $util->process_prettydate('2999-12-31', 4);
	is $result, '2999-12-31', 'ISO format returns YYYY-MM-DD';
};

subtest 'file_to_slug strips root and .md extension' => sub {
	my $root = '/path/to/file';
	my $filename = "$root/about.md";
	my $slug = $util->file_to_slug($filename, { root => $root });
	is $slug, '/about', 'slug returned';
};

subtest 'glob_path absolute pattern' => sub {
	my $root = tempdir(DIR => CWD);

	my $a = path($root, 'a.md')->touch->to_abs->to_string;
	my $b = path($root, 'b.md')->touch->to_abs->to_string;
	my $c = path($root, 'c.md')->touch->to_abs->to_string;
	my $ignore = path($root, 'ignore.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('/*.md', { root => $root->to_abs->to_string, filename => $ignore });
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'correctly matched absolute files';
};

subtest 'glob_path relative pattern' => sub {
	my $root = tempdir(DIR => CWD);

	my $a = path($root, 'a.md')->touch->to_abs->to_string;
	my $b = path($root, 'b.md')->touch->to_abs->to_string;
	my $c = path($root, 'c.md')->touch->to_abs->to_string;
	my $ignore = path($root, 'ignore.md')->touch->to_abs->to_string;

	my @got = $util->glob_path('*.md', { filename => $ignore });
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'correctly matched relative files';
};

done_testing;
