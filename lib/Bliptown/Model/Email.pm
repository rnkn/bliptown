package Bliptown::Model::Email;
use Mojo::Base -base;
use Mojo::Template;
use Mojo::URL;
use Mojo::File qw(path);
use Mojo::Util qw(generate_secret);
use IO::Pipe;
use POSIX qw(strftime);

has 'user';
has 'token';
has 'util';

sub generate_message_id {
	return sprintf '<%s@%s>', substr(generate_secret, 0, 40), $ENV{BLIPTOWN_DOMAIN};
}

sub generate_magic_link_email {
	my ($self, $args) = @_;
	my $recipient_name = $args->{recipient_name} or return;
	my $recipient_email_address = $args->{recipient_email_address} or return;
	my $token = $args->{token} or return;

	my $url = Mojo::URL->new;
	$url->host($ENV{BLIPTOWN_DOMAIN});
	$url->scheme($ENV{BLIPTOWN_SCHEME});
	$url->port($ENV{BLIPTOWN_PORT}) if $ENV{BLIPTOWN_PORT};
	$url->path('_auth');
	$url->query(token => $token);

	my %data = (
		recipient_name => $recipient_name,
		recipient_email_address => $recipient_email_address,
		date => strftime("%a, %d %b %Y %H:%M:%S %z", localtime),
		token => $token,
		host => $ENV{BLIPTOWN_DOMAIN},
		magic_link => $url,
		message_id => generate_message_id,
	);

	my $template = Mojo::Template->new(vars => 1);
	my $email_text = $template->render(<<'EOF', \%data);
From: Bliptown Mayor <mayor@blip.town>
To: <%= $recipient_name %> <<%= $recipient_email_address %>>
Date: <%= $date %>
Message-ID: <%= $message_id %>
Subject: Your Bliptown login link

Hi <%= $recipient_name %>!

Use this link to log in to your account:

<%= $magic_link %>

The link will only work once and is valid for 1 hour.

If you did not request a login for blip.town you can safely discard this email.

Kind regards,

Bliptown Mayor
mayor@blip.town
https://blip.town
EOF

	return $email_text;
}

sub send_contact_form {
	my ($self, $args) = @_;
	my $recipient_name = $args->{recipient_name} or return;
	my $recipient_email_address = $args->{recipient_email_address} or return;
	my $sender_name = $args->{sender_name} || '';
	my $sender_email_address = $args->{sender_email_address} || '';
	my $message = $args->{message} || '';

	my %data = (
		recipient_name => $recipient_name,
		recipient_email_address => $recipient_email_address,
		date => strftime("%a, %d %b %Y %H:%M:%S %z", localtime),
		sender_name => $sender_name,
		sender_email_address => $sender_email_address,
		message => $message,
		message_id => generate_message_id,
	);

	my $template = Mojo::Template->new(vars => 1);
	my $content = $template->render(<<'EOF', \%data);
From: Bliptown Mayor <mayor@blip.town>
To: <%= $recipient_name %> <<%= $recipient_email_address %>>
Date: <%= $date %>
Message-ID: <%= $message_id %>
Subject: You have received a message from your contact form

Hi <%= $recipient_name %>!

You have received a message from your contact form.

Name: <%= $sender_name %>

Email: <%= $sender_email_address %>

Message:

<%= $message %>

Kind regards,

Bliptown Mayor
mayor@blip.town
https://blip.town
EOF

	$self->send_email({
		recipient => $recipient_email_address,
		content => $content,
	});
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
		recipient_name => $username,
		recipient_email_address => $email_address,
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
