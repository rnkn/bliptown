package BliptownTest;
use Mojo::Base -base;
use Mojo::File qw(path curfile tempdir);
use Mojo::SQLite;
use lib curfile->dirname->dirname->sibling('lib');
use Exporter qw(import);
use Test::More;
use Test::Mojo;

use_ok qw(Bliptown::Model::User);
use_ok qw(Bliptown::Model::File);
use_ok qw(Bliptown::Model::Page);
use_ok qw(Bliptown::Model::Metadata);
use_ok qw(Bliptown::Model::Mustache);
use_ok qw(Bliptown::Model::DNS);
use_ok qw(Bliptown::Model::Customer);
use_ok qw(Bliptown::Model::Checkout);
use_ok qw(Bliptown::Model::IPC);
use_ok qw(Bliptown::Model::Email);
use_ok qw(Bliptown::Model::Token);
use_ok qw(Bliptown::Model::Util);

our @EXPORT_OK = qw(create_app create_db);

$ENV{BLIPTOWN_DOMAIN} = 'blip.town';
$ENV{BLIPTOWN_SCHEME} = 'https';
$ENV{BLIPTOWN_PORT} = '443';

sub create_db {
	state $sql = Mojo::SQLite->new(':memory:');
	my $migrations_path = path(curfile->dirname->dirname->sibling('migrations.sql'));
	$sql->migrations->from_file($migrations_path)->migrate($ENV{BLIPTOWN_DB_MIGRATION});
	state $db = $sql->db;
	$db->query('PRAGMA busy_timeout = 10000');
	$db->insert(
		'users', {
			username => 'testuser',
			email => 'testuser@example.com',
			customer_id => 'cus_VCdpxcHMhvORXo',
		}
	);
	return $db;
}

sub create_app {
	state $app = Test::Mojo->new('Bliptown')->app;
	state $db = create_db;

	$app->helper(
		db => sub { return $db }
	);

	return $app;
}

return 1;
