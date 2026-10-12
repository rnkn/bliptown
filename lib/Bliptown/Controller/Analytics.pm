package Bliptown::Controller::Analytics;
use Mojo::Base 'Mojolicious::Controller';
use Digest::SHA qw(hmac_sha1_hex);
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);

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

sub track_visit {
	my $c = shift;
	my $username = $c->session('username') // '';
	my $req_username = $c->get_req_username;
	return $c->reply->not_found unless $req_username;

	if ($username ne $req_username) {
		my $data = $c->get_data // [];
		$c->visitor_log->info($req_username, @$data);
	}

	return $c->render(data => '');
}

sub render_stats {
	my $c = shift;
	my $username = $c->session('username') // '';
	my $stats_path = path($ENV{BLIPTOWN_DATA_HOME}, 'stats', "$username.json");

	my $tables = eval { decode_json($stats_path->slurp) } if -f $stats_path;

	return $c->render(
		template => 'stats',
		page_title => 'Stats',
		tables => $tables // {},
	);
}

return 1;
