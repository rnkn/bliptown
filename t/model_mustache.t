use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use Bliptown::Model::Mustache;
use Bliptown::Model::User;
use Bliptown::Model::Metadata;
use Bliptown::Model::Util;

my $user		= Bliptown::Model::User->new;
my $metadata	= Bliptown::Model::Metadata->new;
my $util		= Bliptown::Model::Util->new;

my $mustache	= Bliptown::Model::Mustache->new(
    req_user	=> 'nobody',
    user		=> $user,
    metadata	=> $metadata,
    util		=> $util,
);

subtest 'process_variables replaces known keys' => sub {
    my $text = <<EOF;
Hello {{ name }}, welcome to {{ place }}.
EOF
    my $args = { metadata => { name => 'Alice', place => 'Earth' } };
    my $out = $mustache->process_variables($text, $args);
    is $out, "Hello Alice, welcome to Earth.\n", 'variables replaced';
};

subtest 'process_variables replaces unknown keys as empty string' => sub {
    my $text = 'Hello {{ unknown }}.';
    my $args = { metadata => {} };
    my $out = $mustache->process_variables($text, $args);
    is $out, 'Hello .', 'unknown key replaced with empty string';
};

subtest 'apply_layout wraps content in section' => sub {
    my $text = 'Hello world!';
    my $args = { metadata => { layout => 'two-column' } };
    my $out  = $mustache->apply_layout($text, $args);
    like $out, qr/<section class="two-column">/, 'section tag opened';
    like $out, qr/<\/section>/, 'section tag closed';
    like $out, qr/Hello world!/, 'content present';
};

# --- process_sections ---
subtest 'process_sections of matched files' => sub {
	my $root = tempdir;
	my $content_1 = <<EOF;
---
title: Post 1
date: 2999-12-31
---
EOF
	my $content_2 = <<EOF;
---
title: Post 2
date: 3000-01-01
---
EOF
	my $ignored_content = <<EOF;
---
title: Ignored Post
date: 3001-01-01
---
EOF
    $root->child('01-post.md')->spew($content_1);
    $root->child('00-post.md')->spew($content_2);
	$root->child('ignored.md')->spew($ignored_content);

    my $text = <<EOF;
{{ # *.md }}
{{ title }}
{{ / }}
EOF
    my $args = {
        root		=> $root->to_abs->to_string,
        filename	=> $root->child('ignored.md')->to_abs->to_string,
        metadata	=> { title => 'Parent Title' },
    };
    my $out = $mustache->process_sections($text, $args);

    like $out, qr/Post 1/, 'content 1 title found';
    like $out, qr/Post 2/, 'content 2 title found';

	unlike $out, qr/Ignored/, 'ignored title ignored';
    ok index($out, 'Post 1') > index($out, 'Post 2'), 'posts are in reverse chronological order';
};

subtest 'process_partials includes partial content' => sub {
    my $root = tempdir;
	$root->child('partial.md')->spew("Partial content.\n");

    my $text = <<EOF;
Hello world!
{{ > partial.md }}
Goodbye world!
EOF
    my $args = {
        root		=> $root->to_abs->to_string,
        filename	=> $root->child('ignored.md')->to_abs->to_string,
        metadata	=> {},
        recur		=> 0,
    };
    my $out = $mustache->process_partials($text, $args);
    like $out, qr/Partial content\./, 'partial content included';
};

subtest 'process_partials error for nonexistent file' => sub {
	my $root = tempdir;
    my $text = "{{ > nonexistent.md }}\n";
    my $args = {
        root		=> $root->to_abs->to_string,
        filename	=> $root->child('ignored.md')->to_abs->to_string,
        metadata	=> {},
        recur		=> 0,
    };
    my $out = $mustache->process_partials($text, $args);
    like $out, qr/Error 404/, '404 error for missing partial';
};

subtest 'process_partials error for excessive recursion' => sub {
	my $root = tempdir;
    my $text_1 = "{{ > recursion-2.md }}\n";
    my $text_2 = "{{ > recursion-1.md }}\n";
    $root->child('recursion-1.md')->spew($text_1);
    $root->child('recursion-2.md')->spew($text_2);

    my $args = {
        root		=> $root->to_abs->to_string,
        filename	=> $root->child('recursion-1.md')->to_abs->to_string,
        metadata	=> {},
        recur		=> 60,
    };
    my $out = $mustache->process_partials($text_1, $args);
    like $out, qr/Error 508/, '508 error for max recursion';
};

done_testing;
