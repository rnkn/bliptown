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
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	my $totp = $c->param('totp') || '';
	my $redirect = $c->param('back_to') || '/';
	if ($c->user->authenticate_user({ username => $username, password => $password, totp => $totp })) {
		$c->session(expiration => 2592000, username => $username);
	} else {
		$c->flash(warning => 'Incorrect credentials');
	}
	return $c->redirect_to($redirect);
}

sub user_logout {
    my $c = shift;
    $c->session(expires => 1);
	return $c->redirect_to('/');
}

return 1;
