package Bliptown::Controller::User;
use Mojo::Base 'Mojolicious::Controller';

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
		$c->flash(info => 'Username unavailable');
		return $c->redirect_to($redirect);
	}

	if (check_duplicate_email($c, { email => $email })) {
		$c->flash(info => 'Account with email already exists');
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

sub user_login {
	my $c = shift;
	my $username	= $c->param('username') // '';
	my $password	= $c->param('password') // '';
	my $totp		= $c->param('totp') // '';
	my $token		= $c->param('token') // '';
	my $redirect	= $c->param('back_to') // '/';

	my $bliptown_domain = $c->stash('bliptown_domain');
	my $host			= $c->req->headers->header('Host') || '';
	$host =~ s/:.*//;
	$host =~ s/^www\.(.+)/$1/;
	$host = $1 if $host =~ /($bliptown_domain)$/;

	if ($token) {
		my $record = $c->token->read_token({ token => $token });

		return $c->render(template => 'invalid', status => 403)
			unless $record;
		if ($record->{expires} <= time) {
			$c->token->delete_token({ token => $token });
			return $c->render(template => 'invalid', status => 403);
		}
		my $token_username = $record->{username};
		return $c->render(template => 'invalid', status => 403)
			unless $token_username;
		if ($username eq $token_username) {
			$c->session(expiration => 2592000, username => $username);
			$c->token->delete_token({ token => $token });
			return $c->redirect_to($redirect);
		}
		$c->token->delete_token({ token => $token });
		return $c->redirect_to($redirect);
	}

	if ($host ne $bliptown_domain) {
		$c->res->code(307);
		$c->redirect_to(
			$c->url_for('user_login'),
			username => $username,
			password => $password,
			totp => $totp,
		);
	}

	my $creds = { username => $username, password => $password, totp => $totp };
	if ($c->user->authenticate_user($creds)) {
		$c->session(expiration => 2592000, username => $username);
		my $user = $c->user->read_user({ key => 'username', username => $username});
		my $custom_domain = $user->{custom_domain};

		if ($custom_domain) {
			my $token = $c->token->create_token({ username => $username });
			my $url = Mojo::URL->new;
			$url->host($custom_domain)->path('login')->query(
				username => $username,
				token => $token
			);
			if ($c->app->mode eq 'production') {
				$url->scheme('https');
			} else {
				$url->scheme('http');
				$url->port(3000);
			}
			return $c->redirect_to($url);
		}
		return $c->redirect_to($redirect);
	}
}

sub user_logout {
    my $c = shift;
    $c->session(expires => 1);
	return $c->redirect_to('/');
}

return 1;
