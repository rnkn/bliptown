package Bliptown::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Crypt::Bcrypt qw(bcrypt bcrypt_check);
use Mojo::Util qw(secure_compare);

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
		}
	);
	return $c->redirect_to($redirect);
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
