use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;
use Test::Mojo;

use BliptownTest qw(create_test create_app);

use_ok qw(Bliptown::Controller::Health);

my $t	= create_test;
my $app = create_app;

my $tempdir = tempdir;
my $health_file = path($tempdir, 'bliptown.health');

$health_file->spew('3');

$ENV{BLIPTOWN_HEALTH_FILE} = $health_file;

$t->get_ok('/_health')->status_is(200)
		->json_is('/BliptownServerWorkers', 3)
		->json_is('/BliptownDatabaseOK', 1);

done_testing;
