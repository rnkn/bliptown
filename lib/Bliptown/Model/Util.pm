package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::URL;
use Mojo::File qw(path);
use POSIX qw(strftime);

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

sub read_file_line {
	my ($self, $file) = @_;
	open(my $fh, '<', $file);
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
	my ($self, $glob, $root, $cur_filename) = @_;
	$glob =~ s/(\.md)?$/.md/;

	if ($glob =~ m{^/}) {
		$glob =~ s{^/}{};
		$glob = path($root, $glob)->to_string;
	}
	else {
		my $file = Mojo::File->new($cur_filename);
		$glob = path($file->dirname, $glob)->to_abs;
	}

	my @filenames = glob $glob;
	@filenames = grep { $_ ne $cur_filename } @filenames;
	@filenames = grep { (split '/', $_)[-1] !~ qr{^_} } @filenames;
	return @filenames;
}

sub filename_to_slug {
	my ($self, $filename, $root) = @_;
	my $rel = Mojo::File->new($filename)->to_rel($root)->to_string;
	$rel =~ s/\.md$//;
	return "/$rel";
}

return 1;
