package Bliptown::Model::DNS;
use Mojo::Base -base;
use Net::DNS;

has 'util';

sub check_domain_dns {
	my ($self, $username, $domain) = @_;
	my $txt_cname		= "_bliptown.$domain";
	my $expected_ipv4	= $ENV{BLIPTOWN_IPV4};
	my $expected_ipv6	= $ENV{BLIPTOWN_IPV6};
	my $expected_txt	= "$username.blip.town";
	my $resolver		= Net::DNS::Resolver->new;
	my $query_A			= $resolver->query($domain, 'A') or return;
	my $query_AAAA		= $resolver->query($domain, 'AAAA') or return;
	my $query_TXT		= $resolver->query($txt_cname, 'TXT') or return;

	my ($record_A, $record_AAAA, $record_TXT);

	foreach my $record ($query_A->answer) {
		next unless $record->type eq 'A';
		$record_A = $record->address;
	}
	foreach my $record ($query_AAAA->answer) {
		next unless $record->type eq 'AAAA';
		$record_AAAA = $record->address;
	}
	foreach my $record ($query_TXT->answer) {
		next unless $record->type eq 'TXT';
		$record_TXT = $record->txtdata;
	}

	return unless (
		$record_A eq $expected_ipv4 &&
		$self->util->ipv6_equal($record_AAAA, $expected_ipv6) &&
		$record_TXT eq $expected_txt
	);
	return 1;
}

return 1;
