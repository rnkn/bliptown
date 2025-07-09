package Bliptown::Controller::User;
use Mojo::Base 'Mojolicious::Controller';

sub validate_user {
	my $c = shift;
	my $validator = Mojolicious::Validator->new;
	my $v = $validator->validation;
	$v->required('username')->like(q/[a-zA-Z][a-zA-Z0-9_-]*$/)->size(1,31);
	$v->required('email')->like(q/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/);
	$v->required('password')->size(8,256);
	return 1 unless $v->has_error;
}

sub user_join {
	my $c = shift;
	my $email = $c->param('email') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	my $redirect_to = $c->param('redirect-to') || '/';
	$c->user->create_user(
		{
			username => $username,
			email => $email,
			password => $password,
		}
	);
	return $c->redirect_to($redirect_to);
}

sub user_login {
	my $c = shift;
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	my $redirect_to = $c->param('redirect-to') || '/';
	if ($c->user->authenticate_user({username => $username, password => $password})) {
		$c->session(expiration => 2592000, username => $username);
		return $c->redirect_to($redirect_to);
	}
	return $c->redirect_to('/nope');
}

sub user_logout {
    my $c = shift;
    $c->session(expires => 1);
	return $c->redirect_to('/');
}

return 1;
