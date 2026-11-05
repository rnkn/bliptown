package Bliptown::Model::DNS;
use Mojo::Base -base;
use List::Util qw(any first);
use Net::DNS;
use NetAddr::IP;

has 'util';

sub in_zone {
    my ($domain, $zone) = @_;
    foreach ($domain, $zone) { s/\.$//; $_ = lc $_ }
    return $domain eq $zone || $domain =~ /\.\Q$zone\E$/ ? 1 : 0;
}

sub get_domain_zone {
    my $domain = shift;
    $domain =~ s/\.$//;
    my @rr = rr($domain, 'SOA');
	return unless @rr;
	my $rr = first { $_->type eq 'SOA' } @rr;
	my $zone = $rr->owner if $rr;
	return lc $zone if $zone;
}

sub check_domain_txt {
	my ($self, $domain, $username) = @_;
	my $zone = get_domain_zone($domain);
	return unless $zone;
	return unless in_zone($domain, $zone);
	my $txt_expected = "$username.blip.town";
	my @rr = rr("_bliptown.$zone", 'TXT');
	my $txt_valid = any { $_->type eq 'TXT' && lc $_->txtdata eq $txt_expected } @rr;
	return $txt_valid;
}

sub check_domain_ipv4 {
	my ($self, $domain) = @_;
	my $ipv4_expected = NetAddr::IP->new($ENV{BLIPTOWN_IPV4});
	my @rr = rr($domain, 'A');
	return unless @rr;
	my $ipv4_valid = any { $_->type eq 'A' && NetAddr::IP->new($_->address) == $ipv4_expected } @rr;
	return $ipv4_valid;
}

sub check_domain_ipv6 {
	my ($self, $domain) = @_;
	my $ipv6_expected = NetAddr::IP->new($ENV{BLIPTOWN_IPV6});
	my @rr = rr($domain, 'AAAA');
	return unless @rr;
	my $ipv6_valid = any { $_->type eq 'AAAA' && NetAddr::IP->new($_->address) == $ipv6_expected } @rr;
	return $ipv6_valid;
}

return 1;
