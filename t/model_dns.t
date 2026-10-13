use Mojo::Base -strict;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib');
use Test::More;

use Bliptown::Model::Util;

use_ok qw(Bliptown::Model::DNS);

my $util	= Bliptown::Model::Util->new;
my $dns		= Bliptown::Model::DNS->new(
	util => $util,
);

subtest 'check_domain_dns' => sub {
	my $username	= 'rnkn';
	my $domain		= 'rnkn.xyz';
	ok $dns->check_domain_dns($username, $domain), 'check_domain_dns validates rnkn.xyz';
	ok ! $dns->check_domain_dns($username, 'example.com'), 'check_domain_dns incorrect domain';
	ok ! $dns->check_domain_dns($username, 'invalid'), 'check_domain_dns invalid domain';
	ok ! $dns->check_domain_dns('nonexistent', $domain), 'check_domain_dns invalid username';
};

done_testing;
