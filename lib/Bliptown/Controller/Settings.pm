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
	my ($c, $context) = @_;
	return unless $context;
	my $domain_coll = $c->sqlite->db->select('users', 'custom_domain')->arrays;
	my @domains = @{$domain_coll->flatten};
	@domains = grep { defined $_ } @domains;
	@domains = sort @domains;
	my %commands = (
		acme => 'update_acme_domains',
		relayd => 'update_relayd_keypairs',
	);
	my $command = $commands{$context};
	return unless $command;
	my $res = $c->ipc->send_message(
		{
			username => 'root',
			command => $command,
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
	my $locked = $username eq 'demo' ? 1 : 0;
	my $user = $c->user->read_user(
		{ key => 'username', username => $username }
	);
	$c->stash(
		title => 'Settings',
		template => 'settings',
		show_sidebar => 1,
		locked => $locked,
		username => $user->{username},
		email => $user->{email},
		custom_domain => $user->{custom_domain},
		date_format => $user->{date_format} // 0,
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
	my $cur_domain = $user->{custom_domain} // '';
	my $new_domain = $params->{custom_domain} // '';
	if ($new_domain ne $cur_domain) {
		$c->update_domain_list('acme');
		$c->provision_cert($new_domain) if $new_domain;
		$c->update_domain_list('relayd');
	}
	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
