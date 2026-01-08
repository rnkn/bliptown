package Bliptown::Controller::Health;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use Mojo::Util qw(trim);

sub health_check {
	my $c = shift;

	my $server_workers = path($ENV{BLIPTOWN_HEALTH_FILE})->slurp;
	my $helper_workers = path($ENV{BLIPTOWN_HELPER_HEALTH_FILE})->slurp;

	my $db_ok = $c->sqlite->db->query('SELECT 1')->hash->{1};

	$c->res->headers->header('X-Bliptown-Server-Workers' => trim $server_workers);
	$c->res->headers->header('X-Bliptown-Helper-Workers' => trim $helper_workers);
	$c->res->headers->header('X-Bliptown-Database-OK' => $db_ok);
	return $c->render(text => 'Health check', format => 'txt');
}

return 1;
