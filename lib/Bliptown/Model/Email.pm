package Bliptown::Model::Email;
use Mojo::Base -base;
use Mojo::Template;
use Mojo::URL;
use Mojo::File qw(path);
use IO::Pipe;
use POSIX qw(strftime);

has 'user';
has 'token';
has 'util';

sub generate_magic_link_email {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $email_address = $args->{email_address} or return;
	my $token = $args->{token} or return;

	my $url = Mojo::URL->new;
	$url->host($ENV{BLIPTOWN_DOMAIN});
	$url->scheme($ENV{BLIPTOWN_SCHEME});
	$url->port($ENV{BLIPTOWN_PORT}) if $ENV{BLIPTOWN_PORT};
	$url->path('_auth');
	$url->query(token => $token);

	my %data = (
		recipient => $username,
		recipient_email_address => $email_address,
		date => strftime("%a, %d %b %Y %H:%M:%S %z", localtime),
		token => $token,
		host => $ENV{BLIPTOWN_DOMAIN},
		magic_link => $url,
	);

	my $template = Mojo::Template->new(vars => 1);
	my $email_text = $template->render(<<'EOF', \%data);
From: Bliptown Mayor <support@blip.town>
To: <%= $recipient %> <<%= $recipient_email_address %>>
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
	my $email_address = $args->{email_address} or return;
	my $custom_domain = $args->{custom_domain} // '';

	my $token = $self->token->create_login_token({
		username => $username,
		custom_domain => $custom_domain,
	});
	return unless $token;

	my $content = $self->generate_magic_link_email({
		username => $username,
		email_address => $email_address,
		token => $token,
	});

	$self->send_email({
		recipient => "$email_address",
		content => $content,
	});
}

sub send_email {
	my ($self, $args) = @_;

	Mojo::IOLoop::Subprocess->new->run(
		sub {
			my $subprocess = shift;
			my $pipe = IO::Pipe->new;
			$pipe->writer($ENV{BLIPTOWN_SENDMAIL_PATH}, $args->{recipient})
				or die "Failed to fork sendmail: $!";

			$pipe->print($args->{content})
				or die 'sendmail: broken pipe';
			$pipe->close;

			return 1;
		},
		sub {
			my ($subprocess, $err, @results) = @_;
			warn "$err" if $err;
		}
	);
}

return 1;
