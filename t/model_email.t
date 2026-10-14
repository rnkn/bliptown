use Mojo::Base -strict;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest qw(create_app);

my $app = create_app;

my $util = Bliptown::Model::Util->new;
my $customer = Bliptown::Model::Customer->new(
	util => $util
);
my $user = Bliptown::Model::User->new(
	db => $app->db,
	customer => $customer,
);
my $token = Bliptown::Model::Token->new(
	db => $app->db
);
my $email = Bliptown::Model::Email->new(
	user => $user,
	token => $token,
	util => $util,
);

my $username = 'testuser';
my $tk = $token->create_login_token({
	username => $username,
});

subtest 'generate_magic_link' => sub {
	my $email_text = $email->generate_magic_link_email({
		username => $username,
		email_address => 'testuser@example.com',
		token => $tk,
	});
	
	ok defined $email_text, 'generate_magic_link_email returns email text';
	like $email_text, qr/From: Bliptown Mayor <support\@blip\.town>/, 'email has correct From header';
	like $email_text, qr/To: testuser <testuser\@example\.com>/, 'email has correct To header';
	like $email_text, qr/Subject: Your Bliptown login link/, 'email has correct Subject';
	like $email_text, qr/Hi testuser!/, 'email personalizes greeting';
	like $email_text, qr{https://blip\.town:443/_auth\?token=$tk}, 'email contains magic link';
};

subtest 'generate_magic_link_email without email' => sub {
	my $email_text = $email->generate_magic_link_email({
		username => 'testuser',
		email => '',
	});
	
	ok !defined $email_text, 'generate_magic_link_email returns undef without email';
};

done_testing;
