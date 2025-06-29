package Bliptown::Controller::User;
use Mojo::Base 'Mojolicious::Controller';

sub user_join {
	my $c = shift;
	my $email = $c->param('email') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
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
