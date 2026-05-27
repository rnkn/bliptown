package Bliptown::Controller::Health;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);

sub health_check {
	my $c = shift;

	my $server_workers = path($ENV{BLIPTOWN_HEALTH_FILE})->slurp;
	my $helper_workers = path($ENV{BLIPTOWN_HELPER_HEALTH_FILE})->slurp;

	my $db_ok = $c->db->query('SELECT 1')->hash->{1};

	$server_workers = $server_workers ? int $server_workers : 0;
	$helper_workers = $helper_workers ? int $helper_workers : 0;

	$c->res->headers->header('X-Bliptown-Server-Workers' => $server_workers);
	$c->res->headers->header('X-Bliptown-Helper-Workers' => $helper_workers);
	$c->res->headers->header('X-Bliptown-Database-OK' => $db_ok);

	my %json = (
		'BliptownServerWorkers' => $server_workers,
		'BliptownHelperWorkers' => $helper_workers,
		'BliptownDatabaseOK' => $db_ok
	);

	return $c->render(json => \%json);
}

return 1;
