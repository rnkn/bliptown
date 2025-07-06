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
	my $upload_paths = $home->child('src', $c->get_user, 'uploads')->list->to_array;
	my %uploads;
	my $id = 0;
	foreach (@$upload_paths) {
		my @stat = stat($_);
		$uploads{$id++} = {
			filename => basename($_),
			size => format_human_size($stat[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stat[9])),
		};
	}
	$c->stash(
		head_add => '',
		template => 'uploads',
		title => 'Uploads',
		uploads => \%uploads,
		# content => $html,
	);
	return $c->render;
}

return 1;
