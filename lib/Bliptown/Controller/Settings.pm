package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub list_settings {
	my $c = shift;
	my $user = $c->user->read_user(
		{ key => 'username', username => $c->session('username') }
	);
	$c->stash(
		title => 'Settings',
		template => 'settings',
		username => $user->{username},
		email => $user->{email},
		custom_domain => $user->{custom_domain},
		sort_new => $user->{sort_new} // 0,
		create_backups => $user->{create_backups} // 0,
	);
	return $c->render;
}

sub save_settings {
	my $c = shift;
	my $user = $c->session('username');
	my @keys_null = qw(custom_domain);
	my @keys_not_null = qw(email new_password);
	my @keys_int = qw(create_backups sort_new);
	my %args; $args{username} = $user;
	foreach (@keys_null) {
		my $v = $c->param($_);
		$args{$_} = $v;
	}
	foreach (@keys_not_null) {
		my $v = $c->param($_);
		$args{$_} = $v if $v;
	}
	foreach (@keys_int) {
		my $v = $c->param($_) // 0;
		$args{$_} = $v;
	}
	$c->user->update_user(\%args);
	return $c->redirect_to($c->url_for);
}

return 1;
