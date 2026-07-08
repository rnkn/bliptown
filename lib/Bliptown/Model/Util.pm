package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::File qw(path);
use POSIX qw(strftime);
use Socket qw(AF_INET6 inet_pton);
use Net::DNS;

sub ipv6_equal {
	my ($self, $addr1, $addr2) = @_;

	my $bin1 = inet_pton(AF_INET6, $addr1);
	my $bin2 = inet_pton(AF_INET6, $addr2);

	return unless ($bin1 && $bin2);
	return 1 if $bin1 eq $bin2;
	return;
}

sub check_domain_dns {
	my ($self, $username, $domain) = @_;
	my $txt_cname		= "_bliptown.$domain";
	my $expected_ipv4	= $ENV{BLIPTOWN_IPV4};
	my $expected_ipv6	= $ENV{BLIPTOWN_IPV6};
	my $expected_txt	= "$username.blip.town";
	my $resolver		= Net::DNS::Resolver->new;
	my @answer_A		= $resolver->query($domain, 'A')->answer or return;
	my @answer_AAAA		= $resolver->query($domain, 'AAAA')->answer or return;
	my @answer_TXT		= $resolver->query($txt_cname, 'TXT')->answer or return;

	my ($record_A, $record_AAAA, $record_TXT);

	foreach my $record (@answer_A) {
		next unless $record->type eq 'A';
		$record_A = $record->address;
	}
	foreach my $record (@answer_AAAA) {
		next unless $record->type eq 'AAAA';
		$record_AAAA = $record->address;
	}
	foreach my $record (@answer_TXT) {
		next unless $record->type eq 'TXT';
		$record_TXT = $record->txtdata;
	}

	return unless (
		$record_A eq $expected_ipv4 &&
		$self->ipv6_equal($record_AAAA, $expected_ipv6) &&
		$record_TXT eq $expected_txt
	);
	return 1;
}

sub create_stripe_url {
	my ($self, $path) = @_;
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host('api.stripe.com');
	$url->path($path);
	$url->userinfo($ENV{BLIPTOWN_STRIPE_API_KEY} . ':');
	return $url;
}

sub split_frontmatter {
	my ($self, $chars) = @_;
	if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
		return ($1, $2);
	}
	return (undef, $chars);
}

sub process_prettydate {
	my ($self, $date, $format) = @_;
	$format //= 0;
	my ($year, $month, $day) = $date =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})/;
	$year = $year - 1900;
	$month--;
	my %date_formats = (
		0 => '%e %B %Y',
		1 => '%B %e, %Y',
		2 => '%B %Y',
		3 => '%Y',
		4 => '%F'
	);
	return strftime($date_formats{$format}, 0, 0, 0, $day, $month, $year) // '';
}

sub glob_path {
	my ($self, $path, $args) = @_;
	$path =~ s/(\.md)?$/.md/;

	if ($path =~ m{^/}) {
		$path =~ s{^/}{};
		$path = path($args->{root}, $path)->to_string;
	}
	else {
		my $file = Mojo::File->new($args->{filename});
		$path = path($file->dirname, $path)->to_abs;
	}

	my @filenames = glob $path;
	@filenames = grep { $_ ne $args->{filename} } @filenames;
	return @filenames;
}

sub file_to_slug {
	my ($self, $filename, $args) = @_;
	my $root = $args->{root};
	my $rel = Mojo::File->new($filename)->to_rel($root)->to_string;
	$rel =~ s/\.md$//;
	return "/$rel";
}

return 1;
