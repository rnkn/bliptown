package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub list_settings {
	my $c = shift;
	my $username = $c->session('username');
	return unless $username;
	my $user = $c->user->read_user(
		{ key => 'username', username => $username }
	);
	$c->stash(
		title => 'Settings',
		template => 'settings',
		show_sidebar => 1,
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
	return unless $username;
	my $user = $c->user->read_user(
		{ key => 'username', username => $username }
	);
	my $cur_domain = $user->{custom_domain};
	my $params = $c->req->params->to_hash;
	$c->user->update_user({ username => $username, %$params });
	my $new_domain = $params->{custom_domain};
	if ($cur_domain && $new_domain and $cur_domain ne $new_domain) {
		$c->ipc->send_message(
			command => 'provision_cert',
			domain => $new_domain,
		)
	};
	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
