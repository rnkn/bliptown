package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';

sub provision_cert {
	my ($c, $domain) = @_;
	my $res = $c->ipc->send_message({
		user => 'root',
		command => 'provision_cert',
		domain => $domain,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	return 1;
}

sub update_domain_list {
	my ($c, $context) = @_;
	return unless $context;
	my $domain_coll = $c->db->select('users', 'custom_domain')->arrays;
	my @domains = @{$domain_coll->flatten};
	@domains = grep { defined $_ } @domains;
	@domains = sort @domains;
	my %commands = (
		acme => 'update_acme_domains',
		relayd => 'update_relayd_keypairs',
	);
	my $command = $commands{$context};
	return unless $command;
	my $res = $c->ipc->send_message({
		user => 'root',
		command => $command,
		domains => \@domains
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	return 1;
}

sub list_settings {
	my $c = shift;
	my $username = $c->session('username');
	return unless $username;
	my $locked = $username eq 'demo' ? 1 : 0;
	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username
	});

	my $customer_id = $user_rec->{customer_id};
	return $c->reply->exception("User $username customer_id not found")
		unless $customer_id;
	my $billing_session = $c->customer->create_billing_session({
		customer_id => $customer_id
	});
	return $c->reply->exception("Cannot create billing sessions for customer_id $customer_id")
		unless $billing_session;
	my $billing_portal_url = $billing_session->{url};

	$c->stash(
		title => 'Settings',
		template => 'settings',
		show_sidebar => 1,
		locked => $locked,
		username => $user_rec->{username} // '',
		email => $user_rec->{email} // '',
		custom_domain => $user_rec->{custom_domain} // '',
		date_format => $user_rec->{date_format} // 0,
		create_backups => $user_rec->{create_backups} // 0,
		billing_portal_url => $billing_portal_url // ''
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

	my $new_domain = $params->{custom_domain} // '';
	my $cur_domain = $user_rec->{custom_domain} // '';

	$c->user->update_user({ username => $username, %$params });

	if ($new_domain ne $cur_domain) {
		$c->update_domain_list('acme');
		if ($new_domain) {
			unless ($c->dns->check_domain_dns($username, $new_domain)) {
				$c->user->update_user({ username => $username, custom_domain => '' });
				$c->flash(info => "Domain $new_domain DNS not set");
				return $c->redirect_to($c->url_for('list_settings'));
			}
			$c->provision_cert($new_domain);
		}
		$c->on(finish => sub { $c->update_domain_list('relayd') });
	}

	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
