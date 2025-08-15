package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub list_settings {
	my $c = shift;
	my $user = $c->user->read_user({ username => $c->session('username')});
	$c->stash(
		title => 'Settings',
		template => 'settings',
		username => $user->{username},
		email => $user->{email},
	);
	return $c->render;
}

return 1;
