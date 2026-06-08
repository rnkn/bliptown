use Mojo::Base -strict;
use File::Basename;
use constant DIR => dirname(__FILE__);
use lib DIR . '/../lib';
use Mojo::File qw(path);
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

subtest 'glob_path absolute with wildcard' => sub {
	my $root = path(DIR, 'tmp_glob_abs')->to_abs;
	$root->remove_tree if -d $root;
	my $dir = path($root, 'dir')->make_path;

	my $a = path($dir, 'a.md')->spurt('a')->to_abs->to_string;
	my $b = path($dir, 'b.md')->spurt('b')->to_abs->to_string;
	my $c = path($dir, 'c.md')->spurt('c')->to_abs->to_string;
	my $ignore = path($dir, 'ignore.md')->spurt('ignore')->to_abs->to_string;

	my @got = $util->glob_path('/dir/*.md', { root => $root->to_string, filename => $ignore });
	my @expected = ($a, $b, $c);
	is_deeply [sort @got], [sort @expected], 'matching absolute files returned, current file excluded';

	$root->remove_tree;
};

subtest 'glob_path relative pattern' => sub {
	my $root = path(DIR, 'tmp_glob_rel')->to_abs;
	$root->remove_tree if -d $root;
	$root->make_path;

	my $one = path($root, '1.md')->spurt('1')->to_abs->to_string;
	my $two = path($root, '2.md')->spurt('2')->to_abs->to_string;
	my $three = path($root, '3.md')->spurt('3')->to_abs->to_string;
	my $filename = path($root, 'cur.md')->spurt('cur')->to_abs->to_string;

	my @got = $util->glob_path('*.md', { filename => $filename });
	my @expected = ($one, $two, $three);
	is_deeply [sort @got], [sort @expected], 'matching sibling files returned, current file excluded';

	$root->remove_tree;
};

done_testing;
