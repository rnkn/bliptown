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
	my $username = $c->session('username');
	my $params = $c->req->params->to_hash;
	$c->user->update_user({ username => $username, %$params });
	return $c->redirect_to($c->url_for('render_page'));
}

sub update_domain_list {
	my $c = shift;
	my $domains_col = $c->sqlite->db->select('users', 'custom_domain')->arrays;
	my @domains = @{$domains_col->flatten};
	@domains = grep { defined $_ } @domains;
	@domains = sort @domains;
	$c->file->update_file(
		{ command => 'update_domain_list', domains => \@domains }
	);
}

return 1;
