use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::Util);

my $util = Bliptown::Model::Util->new;

subtest 'ipv6_equal' => sub {
	my $ipv6_1	= '2001:0db8:0000:0000:0000:0000:0000:0001';
	my $ipv6_2	= '2001:db8::1';
	my $ipv6_3	= '2001:db8::2';
	ok $util->ipv6_equal($ipv6_1, $ipv6_2), 'ipv6_equal validates compressed IPv6 address';
	ok ! $util->ipv6_equal($ipv6_1, 'invalid'), 'ipv6_equal invalid IPv6 address';
	ok ! $util->ipv6_equal($ipv6_1, $ipv6_3), 'ipv6_equal different IPv6 address';
};

subtest 'check_domain_dns' => sub {
	my $username	= 'rnkn';
	my $domain		= 'rnkn.xyz';
	ok $util->check_domain_dns($username, $domain), 'check_domain_dns validates rnkn.xyz';
	ok ! $util->check_domain_dns($username, 'example.com'), 'check_domain_dns incorrect domain';
	ok ! $util->check_domain_dns($username, 'invalid'), 'check_domain_dns invalid domain';
	ok ! $util->check_domain_dns('nonexistent', $domain), 'check_domain_dns invalid usernam';
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
