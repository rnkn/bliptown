use Mojo::Base -strict;
use Mojo::File qw(curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;

my $util	= Bliptown::Model::Util->new;
my $dns		= Bliptown::Model::DNS->new(
	util => $util,
);

$ENV{BLIPTOWN_IPV4} = "46.225.163.173";
$ENV{BLIPTOWN_IPV6} = "2a01:4f8:1c19:6498::1";
my $username		= 'rnkn';
my $domain			= 'rnkn.xyz';

subtest 'check_domain_txt' => sub {
	ok $dns->check_domain_txt($domain, $username), 'check_domain_txt validates rnkn.xyz';
	ok ! $dns->check_domain_txt('example.com', $username), 'check_domain_txt incorrect domain';
	ok ! $dns->check_domain_txt($domain, 'incorrect'), 'check_domain_txt incorrect username';
};

subtest 'check_domain_ipv4' => sub {
	ok $dns->check_domain_ipv4($domain), 'check_domain_ipv4 validates rnkn.xyz';
	ok ! $dns->check_domain_ipv4('example.com'), 'check_domain_ipv4 incorrect domain';
};

subtest 'check_domain_ipv6' => sub {
	ok $dns->check_domain_ipv6($domain), 'check_domain_ipv6 validates rnkn.xyz';
	ok ! $dns->check_domain_ipv6('example.com'), 'check_domain_ipv6 incorrect domain';
};

done_testing;
