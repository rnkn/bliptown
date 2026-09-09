package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::URL;
use Mojo::File qw(path);
use POSIX qw(strftime);

has 'user_path';

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
	$url->host($args->{host} // $ENV{BLIPTOWN_DOMAIN});
	$url->path($args->{path} // '/');
	$url->query(token => $args->{token}, back_to => $args->{redirect});
	return $url;
}

sub read_file_line {
	my ($self, $filename) = @_;
	open(my $fh, '<', $filename);
	my $line = <$fh>;
	close $fh;
	chomp $line;
	return $line;
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
