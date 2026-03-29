use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use BliptownTest qw(new_sqlite_with_users);

use Bliptown::Model::TOTP;
use Bliptown::Model::User;
use Bliptown::Model::Util;

# Set up a user and util instance for process_prettydate tests
my $sql  = new_sqlite_with_users();
my $totp = Bliptown::Model::TOTP->new;
my $user = Bliptown::Model::User->new(sqlite => $sql, totp => $totp);

$user->create_user({
	username => 'dateuser',
	email    => 'dateuser@example.com',
	password => 'password123',
});

my $util_with_user = Bliptown::Model::Util->new(
	req_user => 'dateuser',
	user     => $user,
);

my $util_no_user = Bliptown::Model::Util->new;

subtest 'split_frontmatter with valid frontmatter' => sub {
	my $content = "---\ntitle: Test\n---\nBody content here.";
	my ($yaml, $text) = $util_with_user->split_frontmatter($content);
	ok defined $yaml, 'yaml part extracted';
	like $yaml, qr/title: Test/, 'yaml contains title';
	is $text, 'Body content here.', 'body content correct';
};

subtest 'split_frontmatter without frontmatter' => sub {
	my $content = "Just plain content\nno frontmatter here.";
	my ($yaml, $text) = $util_with_user->split_frontmatter($content);
	ok !defined $yaml, 'no yaml extracted';
	is $text, $content, 'full content returned as text';
};

subtest 'split_frontmatter with empty frontmatter block' => sub {
	my $content = "---\n---\nSome body.";
	my ($yaml, $text) = $util_with_user->split_frontmatter($content);
	ok defined $yaml, 'yaml extracted (even if empty)';
	is $text, 'Some body.', 'body after empty frontmatter';
};

subtest 'file_to_slug strips root and .md extension' => sub {
	my $tmpdir = tempdir(CLEANUP => 1);
	my $root = $tmpdir;
	my $filename = "$tmpdir/about.md";
	my $slug = $util_with_user->file_to_slug($filename, { root => $root });
	is $slug, '/about', 'slug strips root and .md extension';
};

subtest 'file_to_slug with nested path' => sub {
	my $tmpdir = tempdir(CLEANUP => 1);
	my $root = $tmpdir;
	my $filename = "$tmpdir/blog/post.md";
	my $slug = $util_with_user->file_to_slug($filename, { root => $root });
	is $slug, '/blog/post', 'nested slug is correct';
};

subtest 'process_prettydate returns undef without req_user' => sub {
	my $result = $util_no_user->process_prettydate('2024-01-15');
	ok !defined $result, 'returns undef without req_user';
};

subtest 'process_prettydate with default format (0 = day month year)' => sub {
	$user->update_user({ username => 'dateuser', date_format => 0 });
	my $result = $util_with_user->process_prettydate('2024-06-15');
	like $result, qr/June/, 'month name appears in output';
	like $result, qr/2024/, 'year appears in output';
	like $result, qr/15/, 'day appears in output';
};

subtest 'process_prettydate with ISO format (4 = %F)' => sub {
	$user->update_user({ username => 'dateuser', date_format => 4 });
	my $result = $util_with_user->process_prettydate('2024-06-15');
	is $result, '2024-06-15', 'ISO format returns YYYY-MM-DD';
};

done_testing;
