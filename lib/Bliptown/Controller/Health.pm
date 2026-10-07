package Bliptown::Controller::Health;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);

sub health_check {
	my $c = shift;

	my $server_workers = path($ENV{BLIPTOWN_HEALTH_FILE})->slurp;
	my $db_ok = $c->db->query('SELECT 1')->hash->{1};

	$server_workers = $server_workers ? int $server_workers : 0;

	my %json = (
		'BliptownServerWorkers' => $server_workers,
		'BliptownDatabaseOK' => $db_ok
	);

	return $c->render(json => \%json);
}

return 1;
