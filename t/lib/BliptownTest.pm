package BliptownTest;
use Mojo::Base -base;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../../lib');
use Mojo::SQLite;

use Exporter qw(import);

our @EXPORT_OK = qw(create_db);

sub create_db {
	state $sql = Mojo::SQLite->new(":memory:");
	my $migrations_path = path(THIS_DIR, '../../migrations.sql');
	$sql->migrations->from_file($migrations_path)->migrate($ENV{BLIPTOWN_DB_MIGRATION});
	state $db = $sql->db;
	$db->query("PRAGMA busy_timeout = 10000");
	$db->insert(
		'users', {
			username => 'testuser',
			email => 'testuser@example.com',
			customer_id => 'cus_XXXXXXXXXXXXXX',
		}
	);
	return $db;
}

return 1;
