use Mojo::Base -strict;
use lib 't/lib';

use Test::More;

BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use Bliptown::Controller::Snapshots;

my $diff_to_html = \&Bliptown::Controller::Snapshots::diff_to_html;

subtest 'diff_to_html wraps output in section and pre' => sub {
	my $html = $diff_to_html->('');
	like $html, qr{<section class="wide">}, 'wrapped in section.wide';
	like $html, qr{<pre class="diff">}, 'wrapped in pre.diff';
};

subtest 'diff_to_html marks added lines' => sub {
	my $diff = "+added line\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{<span class="addition">\+added line</span>}, 'addition spans wraps + line';
};

subtest 'diff_to_html marks removed lines' => sub {
	my $diff = "-removed line\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{<span class="deletion">-removed line</span>}, 'deletion span wraps - line';
};

subtest 'diff_to_html marks hunk headers' => sub {
	my $diff = "@@ -1,5 +1,6 @@\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{<span class="hunk-header">@@ -1,5 \+1,6 @@</span>}, 'hunk header wrapped';
};

subtest 'diff_to_html passes context lines through unmodified' => sub {
	my $diff = " context line\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{ context line}, 'context line present';
	unlike $html, qr{<span[^>]*> context line}, 'context line not wrapped in span';
};

subtest 'diff_to_html marks separator lines as context' => sub {
	my $diff = "-- \n";
	my $html = $diff_to_html->($diff);
	like $html, qr{-- }, 'separator line present';
};

subtest 'diff_to_html marks other lines as meta' => sub {
	my $diff = "diff --git a/file b/file\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{<span class="meta">diff --git}, 'meta line wrapped';
};

subtest 'diff_to_html escapes HTML entities' => sub {
	my $diff = "+line with <b>tags</b> & entities\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{&lt;b&gt;}, 'angle brackets escaped';
	like $html, qr{&amp;}, 'ampersand escaped';
	unlike $html, qr{<b>}, 'raw b tag not present';
};

subtest 'diff_to_html handles multi-line diffs' => sub {
	my $diff = "@@ -1,3 +1,4 @@\n context\n-old\n+new\n+added\n";
	my $html = $diff_to_html->($diff);
	like $html, qr{class="hunk-header"}, 'hunk header present';
	like $html, qr{class="deletion"}, 'deletion present';
	like $html, qr{class="addition"}, 'addition present';
};

done_testing;
