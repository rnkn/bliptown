package Bliptown::Model::Email;
use Mojo::Base -base;
use Mojo::Template;
use Mojo::URL;
use Mojo::File qw(path);
use Mojo::SMTP::Client;
use POSIX qw(strftime);

has 'user';
has 'token';
has 'util';

sub generate_magic_link_email {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $email = $args->{email} or return;
	my $token = $args->{token} or return;

	my $url = Mojo::URL->new;
	$url->host($ENV{BLIPTOWN_DOMAIN});
	$url->scheme($ENV{BLIPTOWN_SCHEME});
	$url->port($ENV{BLIPTOWN_PORT}) if $ENV{BLIPTOWN_PORT};
	$url->path('_auth');
	$url->query(token => $token);

	my %data = (
		recipient => $username,
		recipient_email => $email,
		date => strftime("%a, %d %b %Y %H:%M:%S %z", localtime),
		token => $token,
		host => $ENV{BLIPTOWN_DOMAIN},
		magic_link => $url,
	);

	my $template = Mojo::Template->new(vars => 1);
	my $email_text = $template->render(<<'EOF', \%data);
From: Bliptown Mayor <support@blip.town>
To: <%= $recipient %> <<%= $recipient_email %>>
Date: <%= $date %>
Message-ID: <%= $token %>@<%= $host %>
Subject: Your Bliptown login link

Hi <%= $recipient %>!

Use this link to log in to your account:

<%= $magic_link %>

The link will only work once and is valid for 1 hour.

If you did not request a login for blip.town you can safely discard this email.

Kind regards,

Bliptown Mayor
support@blip.town
https://blip.town
EOF

	return $email_text;
}

sub send_magic_link {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $email = $args->{email} or return;
	my $custom_domain = $args->{custom_domain} // '';

	my $token = $self->token->create_login_token({
		username => $username,
		custom_domain => $custom_domain,
	});
	return unless $token;

	my $content = $self->generate_magic_link_email({
		username => $username,
		email => $email,
		token => $token,
	});

	$self->send_email({
		recipient => "$username <$email>",
		content => $content,
	});
}

sub send_email {
	my ($self, $args) = @_;
	my $smtp = Mojo::SMTP::Client->new(
		address => $ENV{BLIPTOWN_SMTP_ADDR},
		port => $ENV{BLIPTOWN_SMTP_PORT},
		tls => 1,
	);

	$smtp->send(
		auth => {
			login => $ENV{BLIPTOWN_SMTP_LOGIN},
			password => $ENV{BLIPTOWN_SMTP_PASS},
		},
		from => 'support@blip.town',
		to => $args->{recipient},
		data => $args->{content},
		quit => 1,
		sub {
			my ($smtp, $res) = @_;
			warn $res->error if $res->error;
			return 1;
		}
	);
}

return 1;
