package Bliptown::Controller::Settings;
use Mojo::Base 'Mojolicious::Controller';
use Net::DNS;
use Socket qw(AF_INET6 inet_pton);

sub ipv6_equal {
	my ($addr1, $addr2) = @_;

	my $bin1 = inet_pton(AF_INET6, $addr1);
	my $bin2 = inet_pton(AF_INET6, $addr2);

	return unless ($bin1 && $bin2);
	return 1 if $bin1 eq $bin2;
	return;
}

sub check_domain_dns {
	my ($c, $username, $domain) = @_;
	my $txt_cname		= "_bliptown.$domain";
	my $expected_ipv4	= $ENV{BLIPTOWN_IPV4};
	my $expected_ipv6	= $ENV{BLIPTOWN_IPV6};
	my $expected_txt	= "$username.blip.town";
	my $resolver		= Net::DNS::Resolver->new;
	my @answer_A		= $resolver->query($domain, 'A')->answer or return;
	my @answer_AAAA		= $resolver->query($domain, 'AAAA')->answer or return;
	my @answer_TXT		= $resolver->query($txt_cname, 'TXT')->answer or return;

	my ($record_A, $record_AAAA, $record_TXT);

	foreach my $record (@answer_A) {
		next unless $record->type eq 'A';
		$record_A = $record->address;
	}
	foreach my $record (@answer_AAAA) {
		next unless $record->type eq 'AAAA';
		$record_AAAA = $record->address;
	}
	foreach my $record (@answer_TXT) {
		next unless $record->type eq 'TXT';
		$record_TXT = $record->txtdata;
	}

	return unless ($record_A eq $expected_ipv4 &&
				   ipv6_equal($record_AAAA, $expected_ipv6) &&
				   $record_TXT eq $expected_txt);
	return 1;
}

sub provision_cert {
	my ($c, $domain) = @_;
	my $res = $c->ipc->send_message({
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
		username => 'root',
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
	my $user = $c->user->read_user({
		key => 'username',
		username => $username
	});

	my $customer_id = $user->{customer_id};
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
		username => $user->{username} // '',
		email => $user->{email} // '',
		custom_domain => $user->{custom_domain} // '',
		date_format => $user->{date_format} // 0,
		create_backups => $user->{create_backups} // 0,
		billing_portal_url => $billing_portal_url // ''
	);
	return $c->render;
}

sub save_settings {
	my $c = shift;
	my $username = $c->session('username');
	return unless $username;
	my $user = $c->user->read_user({
		key => 'username',
		username => $username
	});
	my $params = $c->req->params->to_hash;
	$params->{create_backups} //= 0;

	my $new_domain = $params->{custom_domain} // '';
	my $cur_domain = $user->{custom_domain} // '';

	$c->user->update_user({ username => $username, %$params });

	if ($new_domain ne $cur_domain) {
		$c->update_domain_list('acme');
		if ($new_domain) {
			unless ($c->check_domain_dns($username, $new_domain)) {
				$c->user->update_user({ username => $username, domain => '' });
				$c->flash(info => "Domain $new_domain DNS not set");
				return $c->redirect_to(url_for('list_settings'));
			}
			$c->provision_cert($new_domain);
		}
		$c->on(finish => sub { $c->update_domain_list('relayd') });
	}


	return $c->redirect_to($c->url_for('render_page'));
}

return 1;
