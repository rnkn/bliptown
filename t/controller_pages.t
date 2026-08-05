use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;

use_ok qw(Bliptown::Controller::Pages);

my $t				= Test::Mojo->new('Bliptown');
my $app				= $t->app;
my $log				= Mojo::Log->new;
my $debug_messages	= $log->capture('debug');

$app->log($log);

my $ipc = FakeIPC->new;

$app->helper(
	ipc => sub { return $ipc }
);

my $tempbase	= tempdir;
my $user_home	= $tempbase->child('users')->make_path;
my $username	= 'testuser';

$ENV{BLIPTOWN_USER_HOME} = $user_home;

my $user_dir = $user_home->child($username)->make_path;
my $user_domain = "$username.$ENV{BLIPTOWN_DOMAIN}";

$t->app->hook(before_dispatch => sub {
	my $c = shift;
	$c->session(username => $username);
	return 1;
});

my $titlefile = path($user_dir, '_title.txt');
$titlefile->spew('My Site');

my $slug	= 'foo';
my $ext		= 'md';
my $content = <<'EOF';
---
title: Hello World!
date: 2999-12-31
layout: one-column
---
# {{ title }}
{{ > exists }}
{{ > nonexistent }}
{{ > foo* }}
EOF

$t->get_ok($app->url_for('new_page', catchall => $slug) => { Host => $user_domain })->status_is(200)
	->text_like('header h1', qr/New/)
	->attr_is('div#filename input', 'value', $slug)
	->attr_is("div#filename select#ext option[value=\"$ext\"]", 'selected', '')
	->text_is('textarea#content', '');

$t->post_ok($app->url_for('save_page') => { Host => $user_domain } => form => {
	slug		=> $slug,
	ext			=> $ext,
	action		=> 'save',
	content		=> $content,
})->status_is(302);

my $path = path($user_dir, "$slug.$ext");
$path->spew($content);

my $include_content = <<'EOF';
Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
EOF
chomp $include_content;

my $include = path($user_dir, 'exists.md');
$include->spew($include_content);

path($user_dir, 'foobar.md')->touch;
path($user_dir, 'foobaz.md')->touch;

like $debug_messages, qr/Updated file: $path/, 'edit_page updates file';

$t->get_ok($app->url_for('edit_page', catchall => $slug) => { Host => $user_domain })->status_is(200)
	->text_is('header h1 a', $slug)
	->attr_is('div#filename input', 'value', $slug)
	->attr_is("div#filename select#ext option[value=\"$ext\"]", 'selected', '')
	->text_is('textarea#content', $content)
	->attr_is('div#includes a:nth-of-type(1)', 'href', $app->url_for('edit_page', catchall => 'exists.md'))
	->attr_is('div#includes a:nth-of-type(2)', 'href', $app->url_for('edit_page', catchall => 'nonexistent.md'))
	->attr_is('div#includes a:nth-of-type(3)', 'href', $app->url_for('edit_page', catchall => 'foobar.md'))
	->attr_is('div#includes a:nth-of-type(4)', 'href', $app->url_for('edit_page', catchall => 'foobaz.md'));

$t->get_ok($app->url_for('render_raw', catchall => $slug) => { Host => $user_domain })->status_is(200)
	->content_is($content);

$t->get_ok($app->url_for('render_page', catchall => $slug) => { Host => $user_domain })->status_is(200)
	->text_like('head title', qr/My Site . Hello World!/)
	->text_is('main section h1', 'Hello World!')
	->text_is('main section p:nth-of-type(1)', $include_content)
	->text_like('main section p:nth-of-type(2)', qr/404/);

done_testing;
