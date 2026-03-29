package BliptownTest;
use Mojo::Base -strict;
use Mojo::File qw(path tempdir);
use Mojo::SQLite;
use Exporter 'import';

# Polyfill Mojo::Util::generate_secret for Mojolicious < 9.37
BEGIN {
	no warnings 'redefine';
	unless (Mojo::Util->can('generate_secret')) {
		*Mojo::Util::generate_secret = sub {
			my $bytes = '';
			open my $fh, '<', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
			my $total = 0;
			while ($total < 32) {
				my $n = read $fh, my $chunk, 32 - $total;
				die "Cannot read from /dev/urandom: $!" unless defined $n;
				$bytes .= $chunk;
				$total += $n;
			}
			close $fh;
			return unpack 'H*', $bytes;
		};
		push @Mojo::Util::EXPORT_OK, 'generate_secret'
			unless grep { $_ eq 'generate_secret' } @Mojo::Util::EXPORT_OK;
	}
}

our @EXPORT_OK = qw(setup_test_env create_sqlite new_sqlite_with_users);

my $tmpdir;

# Set up a full test environment with temporary directories and environment
# variables. Returns a hashref with useful paths.
sub setup_test_env {
	$tmpdir = tempdir;

	my $user_home = $tmpdir->child('users');
	$user_home->make_path;

	my $log_home = $tmpdir->child('logs');
	$log_home->make_path;

	my $health_file = $tmpdir->child('health');
	$health_file->spew('1');

	my $db_file = $tmpdir->child('test.db');

	$ENV{BLIPTOWN_DOMAIN}              = 'localhost';
	$ENV{BLIPTOWN_SECRET}              = 'test_secret_key_for_testing_only';
	$ENV{BLIPTOWN_DB}                  = $db_file->to_string;
	$ENV{BLIPTOWN_USER_HOME}           = $user_home->to_string;
	$ENV{BLIPTOWN_LOG_HOME}            = $log_home->to_string;
	$ENV{BLIPTOWN_HEALTH_FILE}         = $health_file->to_string;
	$ENV{BLIPTOWN_HELPER_HEALTH_FILE}  = $health_file->to_string;
	$ENV{BLIPTOWN_MD4C_HTML_LIB}       = '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
	$ENV{BLIPTOWN_GEOIP_DB}            = '/dev/null';
	$ENV{BLIPTOWN_HELPER_SOCKET}       = $tmpdir->child('helper.sock')->to_string;

	return {
		dir       => $tmpdir,
		user_home => $user_home,
		log_home  => $log_home,
		db_file   => $db_file,
		health    => $health_file,
	};
}

# Create a fresh Mojo::SQLite instance with all migrations applied.
sub create_sqlite {
	my $db_file = shift;
	my $sql = Mojo::SQLite->new("sqlite:$db_file");
	my $migrations_path = path(__FILE__)->dirname->dirname->dirname->child('migrations.sql');
	$sql->migrations->from_file($migrations_path)->migrate(7);
	return $sql;
}

# Create a fresh Mojo::SQLite instance with an in-memory database.
sub new_sqlite_with_users {
	my $sql = Mojo::SQLite->new(':temp:');
	my $migrations_path = path(__FILE__)->dirname->dirname->dirname->child('migrations.sql');
	$sql->migrations->from_file($migrations_path)->migrate(7);
	return $sql;
}

return 1;
