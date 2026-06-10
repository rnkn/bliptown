use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use Bliptown::Model::User;
use Bliptown::Model::Metadata;
use Bliptown::Model::Mustache;
use Bliptown::Model::Util;
use Bliptown::Model::TOTP;

use_ok qw(Bliptown::Model::Page);

my $db  = create_db;
my $totp = Bliptown::Model::TOTP->new;
my $user = Bliptown::Model::User->new(db => $db, totp => $totp);
my $metadata = Bliptown::Model::Metadata->new;
my $util = Bliptown::Model::Util->new(req_user => undef, user => $user);
my $mustache = Bliptown::Model::Mustache->new(user => $user, metadata => $metadata, util => $util);
my $page = Bliptown::Model::Page->new(
	req_user	=> undef,
	user		=> $user,
	metadata	=> $metadata,
	mustache	=> $mustache,
	util		=> $util,
);

my $tempdir = tempdir;

subtest 'convert_typography en-dashes' => sub {
	my $result = $page->convert_typography('2000--2999');
	is $result, '2000&ndash;2999', 'convert_typography converts double dash to en-dash';
};

subtest 'convert_typography em-dash' => sub {
	my $result = $page->convert_typography('stop---wait');
	is $result, 'stop&mdash;wait', 'convert_typography converts triple dash to em-dash';
};

subtest 'convert_typography smart typography' => sub {
	my $result = $page->convert_typography(q{"Hello world!"});
	like $result, qr/&ldquo;/, 'convert_typography replaces opening double quote';
	like $result, qr/&rdquo;/, 'convert_typography replaces closing double quote';
};

subtest 'convert_typography single quotes' => sub {
	my $result = $page->convert_typography(q{it's});
	like $result, qr/&rsquo;/, 'convert_typography replaces apostrophe';
};

subtest 'render_plaintext txt pre block' => sub {
	my $html = $page->render_plaintext("Hello world in plaintext!\n", 'txt');
	like $html, qr/<pre>Hello world in plaintext!/, 'render_plaintext renders txt in pre';
	like $html, qr{<section}, 'render_plaintext wraps txt in section';
};

subtest 'render_plaintext escape .html' => sub {
	my $html = $page->render_plaintext('<div>Hello world!</div>', 'html');
	like $html, qr/&lt;div&gt;/, 'render_plaintext escapes angle brackets';
	unlike $html, qr/<div>/, 'render_plaintext prevents HTML tags';
};

subtest 'render_plaintext preserve .txt' => sub {
	my $html = $page->render_plaintext('<tag>', 'txt');
	like $html, qr/<tag>/, 'render_plaintext txt content preserved';
};

subtest 'markdown_to_html markdown' => sub {
	my $text = <<EOF;
# Title

Hello world!
EOF
	my $html = $page->markdown_to_html($text);
	like $html, qr/<h1>Title<\/h1>/, 'markdown_to_html renders h1';
	like $html, qr/<p>Hello world!<\/p>/, 'markdown_to_html renders p';
};

subtest 'markdown_to_html bold and italic' => sub {
	my $html = $page->markdown_to_html("**bold** and _italic_");
	like $html, qr/<strong>bold<\/strong>/, 'markdown_to_html renders bold';
	like $html, qr/<em>italic<\/em>/, 'markdown_to_html renders italic';
};

subtest 'markdown_to_html links' => sub {
	my $html = $page->markdown_to_html("[example](https://example.com)");
	like $html, qr{href="https://example\.com"}, 'markdown_to_html renders link href';
	like $html, qr/example<\/a>/, 'markdown_to_html renders link text';
};

subtest 'read_page on a markdown file' => sub {
	my $file = path($tempdir, 'test.md');
	my $text = <<EOF;
# Title

Hello world!
EOF
	$file->spew($text);
	my $result = $page->read_page({ root => $tempdir, filename => $file->to_string });
	like $result->{html}, qr/<h1>Title<\/h1>/, 'read_page returns h1';
	like $result->{html}, qr/<p>Hello world!<\/p>/, 'read_page returns body text';
};

subtest 'read_page markdown file with frontmatter' => sub {
	my $file = path($tempdir, 'frontmatter.md');
	my $content = <<EOF;
---
title: My Page
date: 2999-12-31
---
Hello world!
EOF
	$file->spew($content);
	my $result = $page->read_page({ root => $tempdir, filename => $file->to_string });
	is $result->{metadata}{title}, 'My Page', 'read_page parses title';
	is $result->{metadata}{date}, '2999-12-31', 'read_page parses date';
	like $result->{html}, qr/Hello world!/, 'read_page parses body text';
};

subtest 'read_page txt file' => sub {
	my $file = path($tempdir, 'notes.txt')->spew("plain text content");
	my $result = $page->read_page({ root => $tempdir, filename => $file->to_string });
	like $result->{html}, qr/<pre>plain text content/, 'read_page renders txt as pre';
};

subtest 'read_page on a html file escapes content' => sub {
	my $file = path($tempdir, 'raw.html')->spew('<strong>bold</strong>');
	my $result = $page->read_page({ root => $tempdir, filename => $file->to_string });
	like $result->{html}, qr/&lt;strong&gt;bold/, 'read_page escapes HTML';
};

done_testing;
