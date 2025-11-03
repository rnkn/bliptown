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
		custom_domain => $user->{custom_domain},
	);
	return $c->render;
}

sub save_settings {
	my $c = shift;
	my $u = $c->session('username');
	my @keys_null = qw(custom_domain);
	my @keys_not_null = qw(email new_password);
	my %args; $args{username} = $u;
	foreach (@keys_null) {
		my $v = $c->param($_);
		$args{$_} = $v;
	}
	foreach (@keys_not_null) {
		my $v = $c->param($_);
		$args{$_} = $v if $v;
	}
	say dumper \%args;
	$c->user->update_user(\%args);
	return $c->redirect_to($c->url_for);
}

return 1;
