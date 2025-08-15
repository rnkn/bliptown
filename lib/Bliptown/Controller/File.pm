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
		head => '',
		template => 'files',
		title => 'Files',
		editable => 0,
		redirect => $c->url_for,
		files => \%files,
	);
	return $c->render;
}

sub rename_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $file = $c->get_file($slug);
	my $new_name = $c->param('new_name');
	my $chars = $c->file->read_file({ file => $file })->{chars};
	$c->update_file({ file => $new_name, chars => $chars });

	return $c->redirect_to($c->param('back_to'));
}

sub delete_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $file = $c->get_file($slug);
	$c->file->delete_file({ file => $file });
	return $c->redirect_to($c->param('back_to'));
}

return 1;
