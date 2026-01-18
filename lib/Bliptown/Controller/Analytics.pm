package Bliptown::Controller::Analytics;
use Mojo::Base 'Mojolicious::Controller';
use Digest::SHA qw(hmac_sha1_hex);
use Mojo::File qw(path);

sub track_visit {
	my $c = shift;
	my $username = $c->session('username') // '';
	if ($username eq $c->get_req_user) {
		return $c->render(data => '')
	}
	my $tx = $c->tx;

	my $ip = $tx->req->headers->header('X-Forwarded-For') //
		$tx->remote_address;
	my $country_model = eval { $c->geoip->country(ip => $ip) };
	my $country = $country_model->country->name if $country_model;
	my $ip_hash = hmac_sha1_hex($ip, $c->app->secrets->[0]);

	my $url = Mojo::URL->new($tx->req->headers->referrer);
	my $host = $url->host;
	my $path_query = $url->path_query;

	my @data = (
		$ip_hash						// '',
		$host							// '',
		$path_query						// '',
		$c->param('ref')				// '',
		$tx->req->headers->user_agent	// '',
		$country						// '',
	);

	$c->log_visit(\@data);

	return $c->render(data => '');
}

sub log_visit {
	my ($c, $data) = @_;
	return unless my $req_user = $c->get_req_user;
	my $logpath = path($c->config->{log_home}, 'users', $req_user, 'access.log');
	my $logdir = $logpath->dirname;
	$logdir->make_path unless -d $logdir;
	$logpath->touch unless -f $logpath;
	$logpath->chmod(0600);
	my $log = $c->accesslog($logpath);
	return unless $log;
	$log->info(@$data);
}

return 1;
