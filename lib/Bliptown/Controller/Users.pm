package Bliptown::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Crypt::Bcrypt qw(bcrypt bcrypt_check);
use Mojo::Util qw(secure_compare);
use POSIX qw(strftime);

sub validate_user {
	my ($c, $args) = @_;
	my $v = $c->validation;
	$v->required($args->{username})->like(q/[a-zA-Z][a-zA-Z0-9_-]*$/)->size(1,31);
	$v->required($args->{email})->like(q/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)->size(1,254);
	$v->required($args->{password})->size(8,256);
	return 1 unless $v->has_error;
}

sub check_duplicate_user {
	my ($c, $args) = @_;
	return $c->user->read_user(
		{ key => 'username', username => $args->{username} }
	);
}

sub check_duplicate_email {
	my ($c, $args) = @_;
	return $c->user->read_user(
		{ key => 'email', email => $args->{email} }
	);
}

sub user_join {
	my $c = shift;
	my $email = $c->param('email') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	my $redirect = $c->param('back_to') || '/';

	my $creds = { email => $email, username => $username, password => $password };
	unless (validate_user($c, $creds)) {
		$c->flash(warning => 'Invalid credentials');
		return $c->redirect_to($redirect);
	}

	if (check_duplicate_user($c, { username => $username })) {
		$c->flash(info => 'Username already in use');
		return $c->redirect_to($redirect);
	}

	if (check_duplicate_email($c, { email => $email })) {
		$c->flash(info => 'Account with that email already exists');
		return $c->redirect_to($redirect);
	}

	$c->user->create_user(
		{
			username => $username,
			email => $email,
			password => $password,
			email_verified => 0,
		}
	);

	# Create email verification token
	my $token = $c->email_verification->create_token({ username => $username });

	# Send verification email
	$c->send_verification_email({
		email => $email,
		username => $username,
		token => $token,
	});

	$c->flash(info => 'Account created! Please check your email to verify your account.');
	return $c->redirect_to($redirect);
}

sub send_verification_email {
	my ($c, $args) = @_;
	my $email = $args->{email};
	my $username = $args->{username};
	my $token = $args->{token};

	my $protocol = $c->config->{scheme};
	my $hostname = $c->config->{domain};
	my $port = $c->config->{port};
	my $port_str = $port ? ":$port" : '';

	my $verification_url = "$protocol://$hostname$port_str/verify-email?token=$token";

	my $date = POSIX::strftime("%a, %d %b %Y %H:%M:%S %z", localtime);
	my $email_text = <<"EOF";
From: mayor\@$hostname
To: $email
Date: $date
Message-ID: $token\@$hostname
Subject: Please verify your email address

Hello $username,

Thank you for joining Bliptown! Please verify your email address by clicking the link below:

$verification_url

This link will expire in 24 hours.

If you did not create an account, please ignore this email.

Sincerely,

--
Bliptown
$protocol://$hostname
EOF
	$email_text =~ s/\r?\n/\r\n/g;

	$c->app->log->info("Verification email for $username: $verification_url");

	# If SMTP is configured, send the email
	if ($ENV{BLIPTOWN_SMTP_ADDR}) {
		require Mojo::SMTP::Client;
		my $smtp = Mojo::SMTP::Client->new(
			address => $ENV{BLIPTOWN_SMTP_ADDR},
			port => $ENV{BLIPTOWN_SMTP_PORT},
			tls => 1,
			autodie => 0
		);
		$smtp->send(
			auth => {
				login => $ENV{BLIPTOWN_SMTP_LOGIN},
				password => $ENV{BLIPTOWN_SMTP_PASS},
			},
			from => "noreply\@$hostname",
			to => $email,
			data => $email_text,
			quit => 1,
			sub {
				my ($smtp, $res) = @_;
				if ($res->error) {
					$c->app->log->error('Failed to send verification email: ' . $res->error);
				} else {
					$c->app->log->info("Verification email sent to $email");
				}
			}
		);
	}
}

sub verify_email {
	my $c = shift;
	my $token = $c->param('token') || '';

	my $record = $c->email_verification->read_token({ token => $token });

	if (!$record || !$record->{username} || $record->{expires} <= time) {
		$c->email_verification->delete_token({ token => $token }) if $record;
		return $c->render(
			status => 403,
			template => 'message',
			title => '403 Forbidden',
			content => '403 Forbidden: invalid or expired verification token',
		);
	}

	my $username = $record->{username};

	# Mark email as verified
	$c->user->update_user({
		username => $username,
		email_verified => 1,
	});

	# Delete the verification token
	$c->email_verification->delete_token({ token => $token });

	# Create payment token for Stripe
	my $payment_token = $c->payment_token->create_token({ username => $username });

	# Redirect to subscription page
	return $c->redirect_to("/subscribe?token=$payment_token");
}

sub token_login {
	my ($c, $args)	= @_;
	my $host		= $args->{host} // '';
	my $username	= $args->{username} // '';
	my $token		= $args->{token} // '';
	my $redirect	= $args->{redirect} // '/';
	my $record		= $c->token->read_token({ token => $args->{token} });

	if (! $record || ! $record->{username} || $record->{expires} <= time) {
		$c->token->delete_token({ token => $token }) if $record;
		return $c->render(
			status => 403,
			template => 'message',
			title => '403 Forbidden',
			content => '403 Forbidden: invalid or expired token',
		);
	}

	if ($username eq $record->{username}) {
		$c->stash(custom_session_domain => $host);
		$c->session(expiration => 2592000, username => $username);
		$c->token->delete_token({ token => $token });
		return $c->redirect_to($redirect);
	}

	$c->token->delete_token({ token => $token });
	return $c->redirect_to($redirect);
}

sub login_our_domain {
	my ($c, $args)	= @_;
	my $username	= $args->{username};
	my $password	= $args->{password};
	my $totp		= $args->{totp};
	my $redirect	= $args->{redirect};
	my $url			= Mojo::URL->new;
	my $path		= $c->url_for('user_login')->path->to_string;

	$url->host($c->config->{domain})->path($path);
	$url->scheme($c->config->{scheme});
	$url->port($c->config->{port});
	$c->res->code(307);

	return $c->redirect_to(
		$url,
		username => $username,
		password => $password,
		totp => $totp,
		redirect => $redirect,
	);
}

sub user_login {
	my $c = shift;
	my $username	= $c->param('username') // '';
	my $password	= $c->param('password') // '';
	my $totp		= $c->param('totp') // '';
	my $token		= $c->param('token') // '';
	my $redirect	= $c->param('back_to') // '/';

	my $our_domain = $c->config->{domain};
	my $host = $c->req->url->to_abs->host;
	return unless $host;
	$host =~ s/^www\.//;

	return $c->token_login(
		{
			host		=> $host,
			username	=> $username,
			token		=> $token,
			redirect	=> $redirect
		}
	) if $token;

	return $c->login_our_domain(
		{
			username	=> $username,
			password	=> $password,
			totp		=> $totp,
			redirect	=> $redirect
		}
	) if $host !~ /$our_domain$/;

	my $creds = {
		username => $username,
		password => $password,
		totp => $totp
	};

	if ($c->user->authenticate_user($creds)) {
		$c->session(username => $username);

		my $user = $c->user->read_user({ key => 'username', username => $username});
		my $custom_domain = $user->{custom_domain};

		if ($custom_domain) {
			my $token = $c->token->create_token({ username => $username });
			my $url = Mojo::URL->new;
			my $path = $c->url_for('user_login')->path->to_string;
			$url->host($custom_domain)->path($path)->query(
				username => $username,
				token => $token,
				back_to => $redirect
			);
			$url->scheme($c->config->{scheme});
			$url->port($c->config->{port});
			return $c->redirect_to($url);
		}
		return $c->redirect_to($redirect);
	}
	return $c->render(
		status => 401,
		template => 'message',
		title => '401 Unauthorized',
		content => '401 Unauthorized: incorrect username, password or TOTP',
		username => $username,
	);
}

sub user_logout {
	my $c = shift;
	$c->session(expires => 1);
	return $c->redirect_to('/');
}

return 1;
