package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::URL;
use Mojo::File qw(path);
use Mojo::Util qw(trim);
use Socket qw(AF_INET6 inet_pton);
use POSIX qw(strftime);

has 'user_path';

sub ipv6_equal {
	my ($self, $addr1, $addr2) = @_;

	my $bin1 = inet_pton(AF_INET6, $addr1);
	my $bin2 = inet_pton(AF_INET6, $addr2);

	return unless ($bin1 && $bin2);
	return 1 if $bin1 eq $bin2;
	return;
}

sub format_human_size {
	my ($self, $size) = @_;
	return $size . 'B' if $size < 1024;
	my @units = (qw(K M G T));
	while (@units) {
		my $unit = shift @units;
		$size /= 1024;
		if ($size < 1024) {
			return sprintf('%.2f%s', $size, $unit);
		}
	}
}

sub create_stripe_url {
	my ($self, $path) = @_;
	return unless $path;
	my $url = Mojo::URL->new;
	$url->scheme('https');
	$url->host('api.stripe.com');
	$url->path($path);
	$url->userinfo($ENV{BLIPTOWN_STRIPE_API_KEY} . ':');
	return $url;
}

sub create_bliptown_url {
	my ($self, $args) = @_;
	my $url = Mojo::URL->new;
	$url->scheme($ENV{BLIPTOWN_SCHEME});
	$url->port($ENV{BLIPTOWN_PORT});
	$url->host($args->{host} || $ENV{BLIPTOWN_DOMAIN});
	$url->path($args->{path} || '/');
	$url->query(%{$args->{query} || {}});
	return $url;
}

sub read_file_line {
	my ($self, $filename) = @_;
	return unless -f $filename;
	open(my $fh, '<', $filename);
	my $line = <$fh>;
	close $fh;
	$line = trim $line;
	return $line;
}

sub get_template {
	my ($self, $search_path) = @_;

	my ($template, $content);
	while (1) {
		my $candidate = $search_path->child('_template.md');
		if (-f $candidate) {
			$template = $candidate;
			last;
		}
		last if $search_path le $self->user_path;
		$search_path = $search_path->dirname;
	}

	$content = $template->slurp('UTF-8') if $template;
	return $content;
}

sub split_frontmatter {
	my ($self, $chars) = @_;
	if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
		return ($1, $2);
	}
	return (undef, $chars);
}

sub glob_path {
	my ($self, $glob, $cur_filename) = @_;
	$glob =~ s/(\.md)?$/.md/;

	if ($glob =~ m{^/}) {
		$glob =~ s{^/}{};
		$glob = path($self->user_path, $glob)->to_string;
	}
	else {
		my $path = path($cur_filename);
		$glob = path($path->dirname, $glob)->to_abs->to_string;
	}

	my @filenames = glob $glob;
	@filenames = grep { $_ ne $cur_filename } @filenames;
	@filenames = grep { (split '/', $_)[-1] !~ qr{^_} } @filenames;
	return @filenames;
}

sub filename_to_slug {
	my ($self, $filename) = @_;
	my $rel_filename = path($filename)->to_rel($self->user_path)->to_string;
	$rel_filename =~ s/\.md$//;
	return "/$rel_filename";
}

return 1;
