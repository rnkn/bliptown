package Bliptown::Controller::Analytics;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use Mojo::Util qw(md5_sum);

sub track_visit {
	my $c = shift;
	return $c->render(data => '') if $c->session('username');
	my $tx = $c->tx;

	my $ip = $tx->req->headers->header('X-Forwarded-For');
	my $country_model = eval { $c->geoip->country(ip => $ip) };
	my $country = $country_model->country->name if $country_model;
	my $ip_hash = md5_sum $ip;

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
