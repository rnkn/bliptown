package Bliptown::Controller::Analytics;
use Mojo::Base 'Mojolicious::Controller';
use Digest::SHA qw(hmac_sha1_hex);
use Mojo::File qw(path);

sub get_data {
	my $c			= shift;
	my $tx			= $c->tx	or return;
	my $req			= $tx->req	or return;

	$req->reverse_proxy($c->app->config->{reverse_proxy});

	my $ip			= $tx->remote_address;
	my $ip_hash		= hmac_sha1_hex($ip, $c->app->secrets->[0]);
	my $vhost		= $req->headers->host;
	my $cn			= $c->geoip->country(ip => $ip);
	my $country		= $cn->country->name if $cn;

	my $url			= Mojo::URL->new($req->headers->referrer // '');
	my $host		= $url->host;
	my $path_query	= $url->path_query;

	my @data = (
		$ip_hash						// '',
		$host							// '',
		$path_query						// '',
		$c->param('ref')				// '',
		$tx->req->headers->user_agent	// '',
		$country						// '',
		$vhost							// '',
	);

	return \@data;
}

sub log_data {
	my ($c, $req_user, $data) = @_;
	my $logdir = path($c->config->{log_home}, 'users', $req_user)->make_path;
	my $logpath = path($logdir, 'access.log')->touch->chmod(0600);

	my $log = $c->accesslog($logpath);
	return unless $log;

	$log->info(@$data);
}

sub track_visit {
	my $c = shift;
	my $username = $c->session('username') // '';
	my $req_user = $c->get_req_user;

	if ($req_user && $username ne $req_user) {
		my $data = $c->get_data;
		$c->log_data($req_user, $data);
	}

	return $c->render(data => '');
}

return 1;
