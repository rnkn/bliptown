package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::File qw(path);
use POSIX qw(strftime);

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
