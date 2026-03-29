use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('Bliptown');
$t->get_ok('/')->status_is(200)->content_like(qr/portfolio platform/i);

done_testing();
