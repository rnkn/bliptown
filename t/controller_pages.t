use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use FakeIPC;

use_ok qw(Bliptown::Controller::Pages);

my $t = Test::Mojo->new('Bliptown');
my $log = Mojo::Log->new;
my $debug_messages = $log->capture('debug');
my $app = $t->app;
$app->log($log);

my $ipc = FakeIPC->new;

$app->helper(
	ipc => sub { return $ipc }
);

my $tempbase	= tempdir;
my $user_home	= $tempbase->child('users')->make_path;
my $username	= 'testuser';

$app->config->{user_home} = $user_home;

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
EOF

$t->get_ok("/new/$slug" => { Host => $user_domain })->status_is(200)
	->text_like('header h1', qr/New/)
	->attr_is('div#filename input', 'value', $slug)
	->attr_is("div#filename select#ext option[value=\"$ext\"]", 'selected', '')
	->text_is('textarea#content', '');

$t->post_ok('/edit' => { Host => $user_domain } => form => {
	slug		=> $slug,
	ext			=> $ext,
	action		=> 'save',
	content		=> $content,
})->status_is(302);

my $path = path($user_dir, "$slug.$ext");
$path->spew($content);

like $debug_messages, qr/Updated file: $path/, 'edit_page updates file';

$t->get_ok("/edit/$slug" => { Host => $user_domain })->status_is(200)
	->text_is('header h1 a', $slug)
	->attr_is('div#filename input', 'value', $slug)
	->attr_is("div#filename select#ext option[value=\"$ext\"]", 'selected', '')
	->text_is('textarea#content', $content);

$t->get_ok("/raw/$slug" => { Host => $user_domain })->status_is(200)
	->content_is($content);

$t->get_ok("/$slug" => { Host => $user_domain })->status_is(200)
	->text_like('head title', qr/My Site . Hello World!/)
	->content_like(qr{<h1>Hello World!</h1>});

done_testing;
