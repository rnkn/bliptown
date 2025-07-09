package Bliptown::Controller::Uploads;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename;
use POSIX 'strftime';

my $home = Mojo::Home->new;

sub format_human_size {
	my $size = shift;
    return $size if $size < 1024;
    my @units = (qw(K M G T));
    while (@units) {
		my $unit = shift @units;
        $size /= 1024;
		if ($size < 1024) {
			return sprintf('%.2f%s', $size, $unit);
		}
    }
}

sub list_uploads {
	my $c = shift;
	my $paths = $home->child($c->get_src_dir, $c->get_user, 'assets')->list->to_array;
	my %uploads;
	my $id = 0;
	foreach (@$paths) {
		my @stat = stat($_);
		$uploads{$id++} = {
			filename => basename($_),
			size => format_human_size($stat[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stat[9])),
		};
	}
	$c->stash(
		head => '',
		template => 'uploads',
		title => 'Uploads',
		editable => 0,
		redirect => '',
		uploads => \%uploads,
	);
	return $c->render;
}

return 1;
