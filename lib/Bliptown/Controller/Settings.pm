package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub provision_cert {
	my ($c, $domain) = @_;
	my $res = $c->ipc->send_message({
		system_user => 'root',
		command => 'provision_cert',
		domain => $domain,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	return 1;
}

sub list_settings {
	my $c = shift;
	my $username = $c->session('username');
	return unless $username;
	my $locked = $username eq $ENV{BLIPTOWN_DEMO_USER} ? 1 : 0;
	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username
	});

	my $email = $user_rec->{email};
	return $c->reply->exception("User $username email not found")
		unless $email;

	my $customer_id = $user_rec->{customer_id} // '';
	unless ($customer_id || $locked) {
		return $c->reply->exception("User $username customer_id not found");
	}

	my $create_backups = $user_rec->{create_backups} // 0;

	$c->stash(
		title => 'Settings',
		template => 'settings',
		locked => $locked,
		username => $username,
		email => $email,
		customer_id => $customer_id,
		create_backups => $create_backups,
	);
	return $c->render;
}

sub save_settings {
	my $c = shift;
	my $username = $c->session('username');
	return unless $username;
	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username
	});
	my $params = $c->req->params->to_hash;
	$params->{create_backups} //= 0;

	$c->user->update_user({ username => $username, %$params });

	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
