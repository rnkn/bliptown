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

sub user_login {
	my $c = shift;
	my $username	= $c->param('username') // '';
	my $password	= $c->param('password') // '';
	my $totp		= $c->param('totp') // '';
	my $token		= $c->param('token') // '';
	my $redirect	= $c->param('back_to') // '/';

	my $bliptown_domain = $c->config->{domain};
	my $req_domain = $c->req->url->host;
	$req_domain =~ s/^www\.//;

	if ($token) {
		my $record = $c->token->read_token({ token => $token });

		if (! $record || ! $record->{username} || $record->{expires} <= time) {
			$c->token->delete_token({ token => $token }) if $record;
			return $c->render(
				status => 403,
				template => 'message',
				title => 'Oops...',
				content => '403 Invalid or Expired Token',
			);
		}
		if ($username eq $record->{username}) {
			$c->stash(custom_domain => $req_domain);
			$c->session(expiration => 2592000, username => $username);
			$c->token->delete_token({ token => $token });
			return $c->redirect_to($redirect);
		}
		$c->token->delete_token({ token => $token });
		return $c->redirect_to($redirect);
	}

	if ($req_domain ne $bliptown_domain) {
		my $url = Mojo::URL->new;
		my $path = $c->url_for('user_login')->path->to_string;
		$url->host($bliptown_domain)->path($path);
		if ($c->app->mode eq 'production') {
			$url->scheme('https');
		} else {
			$url->scheme('http');
			$url->port(3000);
		}
		$c->res->code(307);
		return $c->redirect_to(
			$url,
			username => $username,
			password => $password,
			totp => $totp,
		);
	}

	my $creds = { username => $username, password => $password, totp => $totp };
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
	} else {
		return $c->render(
			status => 401,
			template => 'message',
			title => 'Oops...',
			content => '401 Incorrect Username, Password or TOTP',
			username => $username,
		);
	}
	return $c->redirect_to($redirect);
}

sub user_logout {
	my $c = shift;
	$c->session(expires => 1);
	return $c->redirect_to('/');
}

return 1;
