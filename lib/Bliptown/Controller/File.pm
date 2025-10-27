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
	my $user = $c->user->read_user({ username => $c->session('username')});
	my $root = path($c->get_src_dir, $user->{username});
	my $filter = $c->param('filter');
	my $tree = $root->list_tree;

	my @files;
	foreach ($tree->each) {
		my @stats = stat($_);
		my $relpath = $_;
		$relpath =~ s/^$root\/?//;
		my $url = $relpath;
		$url =~ s/\.(md|txt|html|css|js)//;

		push @files, {
			relpath => $relpath,
			url => $url,
			size => format_human_size($stats[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stats[9])),
		}
	};

	@files = grep { $_->{relpath} =~ /$filter/i } @files if $filter;

	if ($user->{sort_files} == 1) {
		@files = sort { $b->{mtime} cmp $a->{mtime} } @files;
	} else {
		@files = sort { $a->{relpath} cmp $b->{relpath} } @files;
	}

	$c->stash(
		template => 'files',
		title => 'Files',
		redirect => $c->url_for,
		files => \@files,
	);
	return $c->render;
}

sub rename_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $old_slug = $c->param('catchall');
	my $new_slug = $c->param('to');
	my $old_file = $c->get_file($old_slug);
	my $new_file = path($root, $new_slug);
	$new_file->dirname->make_path;
	$old_file->copy_to($new_file);
	$old_file->remove;
	$c->flash(info => "$old_slug renamed to $new_slug");
	return $c->redirect_to('list_files');
}

sub delete_file {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->session('username'));
	my $slug = $c->param('catchall');
	my $file = $c->get_file($slug);
	$file->remove;
	$c->flash(info => "$slug deleted");
	return $c->redirect_to('list_files');
}

sub upload_files {
	my $c = shift;
	my $user = $c->user->read_user({ username => $c->session('username')});
	my $root = path($c->get_src_dir, $user->{username});
	my @files;
	foreach (@{$c->req->uploads}) {
		my $f = $_->filename;
		if ($_->size > 1024 * 1024 * 50) {
			$c->flash(warning => "File too large");
			$c->res->code(413);
			return $c->redirect_to('list_files');
		}
		my $path = path($root, $f);
		if (-e $path) {
			$c->flash(warning => "$f already exists!");
			return $c->redirect_to('list_files');
		};
		$_->move_to($path);
	}
	return $c->redirect_to('list_files');
}

return 1;
