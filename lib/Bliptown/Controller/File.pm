package Bliptown::Controller::File;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use POSIX 'strftime';
use Mojo::Util qw(dumper);

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
	my $root = path($c->get_src_dir, $c->session('username'));
	my $f = $root->list_tree;

	my %files;
	foreach ($f->each) {
		my @stats = stat($_);
		my $relpath = $_;
		$relpath =~ s/^$root\/?//;
		my $url = $relpath;
		$url =~ s/\.(md|txt|html|css|js)//;

		$files{$_} = {
			relpath => $relpath,
			url => $url,
			size => format_human_size($stats[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stats[9])),
		}
	};

	if ($filter) {
		foreach (keys %files) {
			delete $files{$_} if $files{$_}{relpath} !~ /$filter/i;
		}
	}

	$c->stash(
		template => 'files',
		title => 'Files',
		redirect => $c->url_for,
		files => \%files,
	);
	return $c->render;
}

sub rename_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $slug = $c->param('catchall');
	my $old_file = $c->get_file($slug);
	my $new_file = path($root, $c->param('to'));
	$old_file->copy_to($new_file);
	$old_file->remove;
	return $c->redirect_to('list_files');
}

sub delete_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $slug = $c->param('catchall');
	my $file = $c->get_file($slug);
	$file->remove;
	return $c->redirect_to('list_files');
}

return 1;
