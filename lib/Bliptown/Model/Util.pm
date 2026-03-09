package Bliptown::Model::Util;
use Mojo::Base -base;
use Mojo::File qw(path);
use POSIX qw(strftime);

has 'req_user';
has 'user';

sub split_frontmatter {
	my ($self, $chars) = @_;
	if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
		return ($1, $2);
	}
	return (undef, $chars);
}

sub get_user_prettydate_format {
	my ($self) = @_;
	my $req_user = $self->req_user;
	my $user = $self->user->read_user(
		{ key => 'username', username => $req_user }
	);
	my %date_formats = (
		0 => '%e %B %Y',
		1 => '%B %e, %Y',
		2 => '%B %Y',
		3 => '%Y',
		4 => '%F'
	);
	return $date_formats{$user->{date_format} // 0};
}

sub process_prettydate {
	my ($self, $date) = @_;
	my ($year, $month, $day) = $date =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})/;
	$year = $year - 1900;
	$month--;
	my $format = $self->get_user_prettydate_format;
	return strftime($format, 0, 0, 0, $day, $month, $year) // '';
}

sub glob_path {
	my ($self, $slug, $args) = @_;
	my $path = $slug;
	$path =~ s/(\.md)?$/.md/;

	if ($path =~ m{^/}) {
		$path =~ s{^/}{};
		$path = path($args->{root}, $path)->to_string;
	} else {
		my $file = Mojo::File->new($args->{filename});
		$path = path($file->dirname, $path)->to_abs;
	}

	my @file_list = glob $path;
	@file_list = grep { $_ ne $args->{filename} } @file_list;
	return @file_list;
}

sub file_to_slug {
	my ($self, $filename, $args) = @_;
	my $root = $args->{root};
	my $rel = Mojo::File->new($filename)->to_rel($root)->to_string;
	$rel =~ s/\.md$//;
	return "/$rel";
}

return 1;
