use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use BliptownTest qw(new_sqlite_with_users);

# Must be set before Bliptown::Model::Page loads (it uses FFI at compile time)
BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use Bliptown::Model::TOTP;
use Bliptown::Model::User;
use Bliptown::Model::Metadata;
use Bliptown::Model::Mustache;
use Bliptown::Model::Util;
use Bliptown::Model::Page;

# Build a Page instance with all dependencies
my $sql  = new_sqlite_with_users();
my $totp = Bliptown::Model::TOTP->new;
my $user = Bliptown::Model::User->new(sqlite => $sql, totp => $totp);
my $meta = Bliptown::Model::Metadata->new;
my $util = Bliptown::Model::Util->new(req_user => undef, user => $user);
my $must = Bliptown::Model::Mustache->new(user => $user, metadata => $meta, util => $util);
my $page = Bliptown::Model::Page->new(
	req_user => undef,
	user     => $user,
	metadata => $meta,
	mustache => $must,
	util     => $util,
);

my $tmpdir = tempdir(CLEANUP => 1);

subtest 'convert_typography replaces double dashes with en-dash' => sub {
	my $result = $page->convert_typography('1990--2000');
	is $result, '1990&ndash;2000', 'double dash becomes en-dash';
};

subtest 'convert_typography replaces triple dashes with em-dash' => sub {
	my $result = $page->convert_typography('stop---wait');
	is $result, 'stop&mdash;wait', 'triple dash becomes em-dash';
};

subtest 'convert_typography replaces straight quotes with curly quotes' => sub {
	my $result = $page->convert_typography(q{"hello"});
	like $result, qr/&ldquo;/, 'opening double quote replaced';
	like $result, qr/&rdquo;/, 'closing double quote replaced';
};

subtest 'convert_typography handles single quotes' => sub {
	my $result = $page->convert_typography(q{it's});
	like $result, qr/&rsquo;/, 'apostrophe replaced with right single quote';
};

subtest 'render_plaintext wraps text in pre block' => sub {
	my $html = $page->render_plaintext("some plain text\n", 'txt');
	like $html, qr/<pre>some plain text/, 'text appears in pre element';
	like $html, qr{<section}, 'wrapped in section';
};

subtest 'render_plaintext escapes HTML for html extension' => sub {
	my $html = $page->render_plaintext('<div>test</div>', 'html');
	like $html, qr/&lt;div&gt;/, 'angle brackets are escaped';
	unlike $html, qr/<div>/, 'raw tags not present';
};

subtest 'render_plaintext does not escape for txt extension' => sub {
	my $html = $page->render_plaintext('<tag>', 'txt');
	like $html, qr/<tag>/, 'txt content not escaped';
};

subtest 'markdown_to_html converts basic markdown' => sub {
	my $html = $page->markdown_to_html("# Hello\n\nParagraph.");
	like $html, qr/<h1>Hello<\/h1>/, 'h1 heading rendered';
	like $html, qr/<p>Paragraph\.<\/p>/, 'paragraph rendered';
};

subtest 'markdown_to_html converts bold and italic' => sub {
	my $html = $page->markdown_to_html("**bold** and _italic_");
	like $html, qr/<strong>bold<\/strong>/, 'bold rendered';
	like $html, qr/<em>italic<\/em>/, 'italic rendered';
};

subtest 'markdown_to_html converts links' => sub {
	my $html = $page->markdown_to_html("[example](https://example.com)");
	like $html, qr{href="https://example\.com"}, 'link href rendered';
	like $html, qr/example<\/a>/, 'link text rendered';
};

subtest 'read_page on a markdown file' => sub {
	my $file = path($tmpdir, 'test.md');
	$file->spew("# Title\n\nHello world.");
	my $result = $page->read_page({ root => $tmpdir, filename => $file->to_string });
	like $result->{html}, qr/<h1>Title<\/h1>/, 'heading in output';
	like $result->{html}, qr/Hello world/, 'body text in output';
};

subtest 'read_page on a markdown file with frontmatter' => sub {
	my $file = path($tmpdir, 'frontmatter.md');
	$file->spew("---\ntitle: My Page\ndate: 2024-03-01\n---\n\nContent here.");
	my $result = $page->read_page({ root => $tmpdir, filename => $file->to_string });
	is $result->{metadata}{title}, 'My Page', 'title from frontmatter';
	is $result->{metadata}{date}, '2024-03-01', 'date from frontmatter';
	like $result->{html}, qr/Content here/, 'body content present';
};

subtest 'read_page on a txt file renders as plaintext' => sub {
	my $file = path($tmpdir, 'notes.txt');
	$file->spew("plain text content");
	my $result = $page->read_page({ root => $tmpdir, filename => $file->to_string });
	like $result->{html}, qr/<pre>plain text content/, 'txt rendered as pre';
};

subtest 'read_page on a html file escapes content' => sub {
	my $file = path($tmpdir, 'raw.html');
	$file->spew('<b>bold</b>');
	my $result = $page->read_page({ root => $tmpdir, filename => $file->to_string });
	like $result->{html}, qr/&lt;b&gt;bold/, 'HTML content is escaped';
};

done_testing;
