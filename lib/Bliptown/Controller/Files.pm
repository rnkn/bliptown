package Bliptown::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use POSIX 'strftime';
use Mojo::Util qw(dumper);

my $home = Mojo::Home->new;

sub format_human_size {
	my $size = shift;
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

sub list_files {
	my $c = shift;
	my $filter = $c->param('filter');
	my $root = path($c->get_src_dir, $c->get_user);
	my $f = $root->list_tree;

	my %files;
	foreach ($f->each) {
		my @stat = stat($_);
		my $relpath = $_;
		$relpath =~ s/^$root\/?//;
		my $url = $relpath;
		$url =~ s/\.(md|txt|html|css|js)//;

		$files{$_} = {
			relpath => $relpath,
			url => $url,
			size => format_human_size($stat[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stat[9])),
		}
	};

	if ($filter) {
		foreach (keys %files) {
			delete $files{$_} if $files{$_}{relpath} !~ /$filter/;
		}
	}

	$c->stash(
		head => '',
		template => 'files',
		title => 'Files',
		editable => 0,
		redirect => $c->url_for,
		files => \%files,
	);
	return $c->render;
}

sub delete_file {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to');
	my $root = path($c->get_src_dir, $c->get_user);
	my $file = $c->get_file($slug);
	$c->source->delete_source({ file => $file });
	return $c->redirect_to($redirect);
}

return 1;
