package Bliptown::Controller::Email;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util 'generate_secret';
use POSIX 'strftime';

sub generate_email_confirmation {
	my ($email_address, $token, $protocol, $hostname) = @_;
	my $date = strftime("%a, %d %b %Y %H:%M:%S %z", localtime);
	my $email_text = <<"EOF";
From: mayor\@blip.town
To: $email_address
Date: $date
Message-ID: $token\@$hostname
Subject: Please confirm you email address

Hello,

Thank you for creating an account at Bliptown. Please confirm your
email address by following the link below:

$protocol://$hostname/confirm?token=$token

If you did not create an account, please ignore this email.

Sincerely,

--
Paul W. Rankin
Bliptown Mayor
https://blip.town
EOF
	$email_text =~ 's/\r?\n/\r\n/g';
	return $email_text;
}

sub send_email_confirmation {
	my $c = shift;
	my $email_address = 'rnkn@rnkn.xyz'; # <-- FIXME
	my ($protocol, $hostname);
	if ($c->app->mode eq 'development') {
		$protocol = 'http';
		$hostname = 'blip.local:3000';
	} else {
		$protocol = 'https';
		$hostname = 'blip.town';
	}
	my $token = generate_secret;
	my $email_text = generate_email_confirmation(
		$email_address, $token, $protocol, $hostname
	);

	$c->app->log->debug($email_text);

	my $smtp = Mojo::SMTP::Client->new(
		address => $ENV{'BLIPTOWN_SMTP_ADDR'},
		port => $ENV{'BLIPTOWN_SMTP_PORT'},
		tls => 1,
		autodie => 1
	);
	$smtp->send(
		auth => {
			login => $ENV{'BLIPTOWN_SMTP_LOGIN'},
			password => $ENV{'BLIPTOWN_SMTP_PASS'},
		},
		from => 'rnkn@rnkn.xyz',
        to => 'rnkn@rnkn.xyz',
        data => $email_text,
        quit => 1,
		sub {
			my ($smtp, $res) = @_;
			$c->app->log->debug($res->error ? 'Failed to send email: ' . $res->error : 'Confirmation email sent to $email_address');
        }
	);
	$c->stash(
		template => 'default',
	)
};

return 1;
