package BliptownTest;
use Mojo::Base -base;
use Mojo::File qw(path curfile tempdir);
use Mojo::SQLite;
use lib curfile->dirname->dirname->sibling('lib'), curfile->dirname;
use Exporter qw(import);
use Test::More;
use Test::Mojo;

use Bliptown::Model::User;
use Bliptown::Model::File;
use Bliptown::Model::Page;
use Bliptown::Model::Metadata;
use Bliptown::Model::Mustache;
use Bliptown::Model::DNS;
use Bliptown::Model::Customer;
use Bliptown::Model::Checkout;
use Bliptown::Model::IPC;
use Bliptown::Model::Email;
use Bliptown::Model::Token;
use Bliptown::Model::Util;

use FakeDNS;
use FakeEmail;
use FakeIPC;
use FakeVisitorLog;

use constant CSRF_TOKEN => '0' x 80;

our @EXPORT_OK = qw(create_test create_app create_db CSRF_TOKEN);

$ENV{BLIPTOWN_DOMAIN}		= 'blip.town';
$ENV{BLIPTOWN_SCHEME}		= 'https';
$ENV{BLIPTOWN_PORT}			= '443';
$ENV{BLIPTOWN_DATA_HOME}	= tempdir;
$ENV{BLIPTOWN_LOG_HOME}		= tempdir;

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

sub create_test {
	state $t = Test::Mojo->new('Bliptown');
	return $t;
}

sub create_app {
	state $app = create_test->app;
	state $db = create_db;
	state $ipc = FakeIPC->new;
	state $dns = FakeDNS->new;
	state $email = FakeEmail->new;

	$app->helper(
		db => sub { return $db }
	);
	$app->helper(
		ipc => sub { return $ipc }
	);
	$app->helper(
		dns => sub { return $dns }
	);
	$app->helper(
		email => sub { return $email }
	);

	$app->hook(before_dispatch => sub {
		my $c = shift;
		$c->session->{csrf_token} = '0' x 40;
		return 1;
	});

	return $app;
}

return 1;
