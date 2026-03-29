use Mojo::Base -strict;
use lib 't/lib';

use Test::More;
use Mojo::File qw(path);

BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use BliptownTest qw(setup_test_env);
use Test::Mojo;

my $env = setup_test_env();
my $mayor_dir = path($env->{user_home}, 'mayor');
$mayor_dir->make_path;
path($mayor_dir, 'index.md')->spew(
	"# Welcome\n\nBliptown is a portfolio platform."
);

my $t = Test::Mojo->new('Bliptown');
$t->get_ok('/' => { Host => 'localhost' })->status_is(200)->content_like(qr/portfolio platform/i);

done_testing();
