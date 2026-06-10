use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use Bliptown::Model::User;
use Bliptown::Model::Metadata;
use Bliptown::Model::Util;

use_ok qw(Bliptown::Model::Mustache);

my $user		= Bliptown::Model::User->new;
my $metadata	= Bliptown::Model::Metadata->new;
my $util		= Bliptown::Model::Util->new;

my $mustache	= Bliptown::Model::Mustache->new(
    req_user	=> 'nobody',
    user		=> $user,
    metadata	=> $metadata,
    util		=> $util,
);

subtest 'process_variables known keys' => sub {
    my $text = <<EOF;
Hello {{ name }}, welcome to {{ place }}.
EOF
    my $args = { metadata => { name => 'Alice', place => 'Earth' } };
    my $out = $mustache->process_variables($text, $args);
    is $out, "Hello Alice, welcome to Earth.\n", 'process_variables replaces variables';
};

subtest 'process_variables unknown keys' => sub {
    my $text = 'Hello {{ unknown }}.';
    my $args = { metadata => {} };
    my $out = $mustache->process_variables($text, $args);
    is $out, 'Hello .', 'process_variables replaces unknown key with empty string';
};

subtest 'apply_layout' => sub {
    my $text = 'Hello world!';
    my $args = { metadata => { layout => 'two-column' } };
    my $out  = $mustache->apply_layout($text, $args);
    like $out, qr/<section class="two-column">/, 'apply_layout opens section tag';
    like $out, qr/<\/section>/, 'apply_layout closes section tag';
    like $out, qr/Hello world!/, 'apply_layout returns body text';
};

# --- process_sections ---
subtest 'process_sections matching files' => sub {
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

	like $out, qr/Post 1/, 'process_sections returns content 1 title';
	like $out, qr/Post 2/, 'process_sections returns content 2 title';
	unlike $out, qr/Ignored/, 'process_sections ignores ignored file';
	ok index($out, 'Post 1') > index($out, 'Post 2'), 'process_sections returns posts in reverse chronological order';
};

subtest 'process_partials partials' => sub {
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
    like $out, qr/Partial content\./, 'process_partials returns partial content';
};

subtest 'process_partials nonexistent file' => sub {
	my $root = tempdir;
    my $text = "{{ > nonexistent.md }}\n";
    my $args = {
        root		=> $root->to_abs->to_string,
        filename	=> $root->child('ignored.md')->to_abs->to_string,
        metadata	=> {},
        recur		=> 0,
    };
    my $out = $mustache->process_partials($text, $args);
    like $out, qr/Error 404/, 'process_partials returns 404 for missing partial';
};

subtest 'process_partials excessive recursion' => sub {
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
    like $out, qr/Error 508/, 'process_partials returns 508 for max recursion';
};

done_testing;
