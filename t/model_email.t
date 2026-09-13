use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use BliptownTest qw(create_db);

use Bliptown::Model::Util;
use Bliptown::Model::Token;
use Bliptown::Model::User;

use_ok qw(Bliptown::Model::Email);

my $db		= create_db;
my $util	= Bliptown::Model::Util->new;
my $token	= Bliptown::Model::Token->new(db => $db);
my $user	= Bliptown::Model::User->new(db => $db);

my $email_model = Bliptown::Model::Email->new(
	user	=> $user,
	token	=> $token,
	util	=> $util,
);

subtest 'generate_magic_link_email omits without username' => sub {
	my $text = $email_model->generate_magic_link_email({
		email => 'alice@example.com',
	});
	ok !defined $text, 'generate_magic_link_email returns undef without username';
};

subtest 'generate_magic_link_email omits without email' => sub {
	my $text = $email_model->generate_magic_link_email({
		username => 'alice',
	});
	ok !defined $text, 'generate_magic_link_email returns undef without email';
};

subtest 'generate_magic_link_email renders login link' => sub {
	local $ENV{BLIPTOWN_DOMAIN}	= 'blip.town';
	local $ENV{BLIPTOWN_SCHEME}	= 'https';
	local $ENV{BLIPTOWN_PORT}	= '';

	my $text = $email_model->generate_magic_link_email({
		username	=> 'alice',
		email		=> 'alice@example.com',
	});

	ok defined $text, 'generate_magic_link_email returns email text';
	like $text, qr/^From: Bliptown Mayor <support\@blip\.town>/m,
		'email has From header';
	like $text, qr/^To: alice <alice\@example\.com>/m,
		'email has To header with recipient and address';
	like $text, qr/^Subject: Your Bliptown login link$/m,
		'email has Subject header';
	like $text, qr{https://blip\.town/_auth\?token=}, 'email contains magic link URL';
	like $text, qr{is valid for 1 hour},
		'email mentions 1 hour validity';
	like $text, qr{Hi alice!}, 'email greets the recipient by username';
};

subtest 'generate_magic_link_email uses custom domain in token' => sub {
	local $ENV{BLIPTOWN_DOMAIN}	= 'blip.town';
	local $ENV{BLIPTOWN_SCHEME}	= 'https';
	local $ENV{BLIPTOWN_PORT}	= '';

	my $text = $email_model->generate_magic_link_email({
		username		=> 'bob',
		email			=> 'bob@example.com',
		custom_domain	=> 'bob.example.com',
	});

	ok defined $text, 'generate_magic_link_email accepts custom_domain';
	my ($token_str) = $text =~ m{[?&]token=([^&\s]+)};
	ok defined $token_str, 'email contains a token';
	my $token_rec = $token->read_login_token({ token => $token_str });
	ok defined $token_rec, 'token was persisted to database';
	is $token_rec->{custom_domain}, 'bob.example.com',
		'token record stores the custom domain';
};

subtest 'generate_magic_link_email sets port when configured' => sub {
	local $ENV{BLIPTOWN_DOMAIN}	= 'blip.town';
	local $ENV{BLIPTOWN_SCHEME}	= 'http';
	local $ENV{BLIPTOWN_PORT}	= '3000';

	my $text = $email_model->generate_magic_link_email({
		username	=> 'carol',
		email		=> 'carol@example.com',
	});

	like $text, qr{http://blip\.town:3000/_auth\?token=},
		'email link includes port from BLIPTOWN_PORT';
};

subtest 'send_magic_link omits without username' => sub {
	my $ok = $email_model->send_magic_link({});
	ok !defined $ok, 'send_magic_link returns undef without username';
};

subtest 'send_magic_link omits for nonexistent user' => sub {
	my $ok = $email_model->send_magic_link({ username => 'nobody' });
	ok !defined $ok, 'send_magic_link returns undef for unknown user';
};

subtest 'send_magic_link omits for user without email' => sub {
	$db->insert('users', { username => 'noemail', email => '' });

	local $ENV{BLIPTOWN_DOMAIN}		= 'blip.town';
	local $ENV{BLIPTOWN_SCHEME}		= 'https';
	local $ENV{BLIPTOWN_PORT}		= '';
	local $ENV{BLIPTOWN_DATA_HOME}	= tempdir;
	local $ENV{BLIPTOWN_SMTP_ADDR}	= 'localhost';
	local $ENV{BLIPTOWN_SMTP_PORT}	= '465';
	local $ENV{BLIPTOWN_SMTP_LOGIN}	= 'login';
	local $ENV{BLIPTOWN_SMTP_PASS}	= 'pass';

	my $ok = $email_model->send_magic_link({ username => 'noemail' });
	ok !defined $ok, 'send_magic_link returns undef for user without email';
};

done_testing;
