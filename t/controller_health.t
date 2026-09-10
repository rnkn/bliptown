use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use BliptownTest qw(create_db);

use_ok qw(Bliptown::Controller::Health);

my $t = Test::Mojo->new('Bliptown');
my $app = $t->app;

$app->helper(
	db => sub { return create_db }
);

my $tempdir = tempdir;
my $health_file = path($tempdir, 'server_health.txt');
my $helper_health_file = path($tempdir, 'helper_health.txt');

$health_file->spew('3');
$helper_health_file->spew('2');

local $ENV{BLIPTOWN_HEALTH_FILE} = $health_file;
local $ENV{BLIPTOWN_HELPER_HEALTH_FILE} = $helper_health_file;

$t->get_ok('/health')->status_is(200)
		->json_is('/BliptownServerWorkers', 3)
		->json_is('/BliptownHelperWorkers', 2)
		->json_is('/BliptownDatabaseOK', 1);

done_testing;
