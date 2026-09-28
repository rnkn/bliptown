use Mojo::Base -strict;
use Mojo::File qw(path curfile tempdir);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::DNS);

my $dns = Bliptown::Model::DNS->new;

subtest 'check_domain_dns' => sub {
	my $username	= 'rnkn';
	my $domain		= 'rnkn.xyz';
	ok $dns->check_domain_dns($username, $domain), 'check_domain_dns validates rnkn.xyz';
	ok ! $dns->check_domain_dns($username, 'example.com'), 'check_domain_dns incorrect domain';
	ok ! $dns->check_domain_dns($username, 'invalid'), 'check_domain_dns invalid domain';
	ok ! $dns->check_domain_dns('nonexistent', $domain), 'check_domain_dns invalid usernam';
};

done_testing;
