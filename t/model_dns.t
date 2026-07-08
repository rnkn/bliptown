use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::DNS);

my $dns = Bliptown::Model::DNS->new;

subtest 'ipv6_equal' => sub {
	my $ipv6_1	= '2001:0db8:0000:0000:0000:0000:0000:0001';
	my $ipv6_2	= '2001:db8::1';
	my $ipv6_3	= '2001:db8::2';
	ok $dns->ipv6_equal($ipv6_1, $ipv6_2), 'ipv6_equal validates compressed IPv6 address';
	ok ! $dns->ipv6_equal($ipv6_1, 'invalid'), 'ipv6_equal invalid IPv6 address';
	ok ! $dns->ipv6_equal($ipv6_1, $ipv6_3), 'ipv6_equal different IPv6 address';
};

subtest 'check_domain_dns' => sub {
	my $username	= 'rnkn';
	my $domain		= 'rnkn.xyz';
	ok $dns->check_domain_dns($username, $domain), 'check_domain_dns validates rnkn.xyz';
	ok ! $dns->check_domain_dns($username, 'example.com'), 'check_domain_dns incorrect domain';
	ok ! $dns->check_domain_dns($username, 'invalid'), 'check_domain_dns invalid domain';
	ok ! $dns->check_domain_dns('nonexistent', $domain), 'check_domain_dns invalid usernam';
};

done_testing;
