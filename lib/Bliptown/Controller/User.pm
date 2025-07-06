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
	# if username already in db -> duplicate_username_error
	# if email already in db, with email confirm with mismatch username -> duplicate_email_error
	# if already in db, email unconfirm -> send_email_confirmation
	# if not in db -> create_user -> loop
}

sub user_login {
	my $c = shift;
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	if ($c->users->authenticate_user($username, $password)) {
		$c->session(expiration => 2592000);
	}
}

sub user_logout {
    my $c = shift;
    $c->session(expires => 1);
}

return 1;
