package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub provision_cert {
	my ($c, $domain) = @_;
	my $res = $c->ipc->send_message(
		{
			username => 'root',
			command => 'provision_cert',
			domain => $domain,
		});
	return $c->reply->exception($res->{error}) if $res->{error};
	return 1;
}

sub update_domain_list {
	my $c = shift;
	my $coll = $c->sqlite->db->select('users', 'custom_domain')->arrays;
	my @domains = @{$coll->flatten};
	@domains = grep { defined $_ } @domains;
	@domains = sort @domains;
	my $res = $c->ipc->send_message(
		{
			username => 'root',
			command => 'update_domain_list',
			domains => \@domains
		}
	);
	return $c->reply->exception($res->{error}) if $res->{error};
	return 1;
}

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
	my $params = $c->req->params->to_hash;
	$c->user->update_user({ username => $username, %$params });
	my $cur_domain = $user->{custom_domain} || '';
	my $new_domain = $params->{custom_domain} || '';
	if (($new_domain || $cur_domain) && $new_domain ne $cur_domain) {
		$c->update_domain_list;
	}
	if ($new_domain && $new_domain ne $cur_domain) {
		$c->provision_cert($new_domain);
	}
	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
