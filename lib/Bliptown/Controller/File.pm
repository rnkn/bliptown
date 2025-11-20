package Bliptown::Controller::File;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use POSIX qw(strftime);

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
	my $user = $c->user->read_user(
		{ key => 'username', username => $c->session('username') }
	);
	my $root = path($c->get_user_home, $user->{username});
	my $filter = $c->param('filter');
	my $tree = $root->list_tree;

	my @files;
	foreach ($tree->each) {
		my @stats = stat($_);
		my $rel_filename = $_->to_rel($root)->to_string;
		my $url = $rel_filename; $url =~ s/\.(md|txt|html|css|js)$//;

		push @files, {
			filename => $rel_filename,
			url => $url,
			size => format_human_size($stats[7]),
			mtime => strftime('%Y-%m-%d %H:%M', localtime($stats[9])),
		}
	};

	@files = grep { $_->{filename} =~ /$filter/ } @files if $filter;

	if ($user->{sort_new} == 1) {
		@files = sort { $b->{mtime} cmp $a->{mtime} } @files;
	} else {
		@files = sort { $a->{filename} cmp $b->{filename} } @files;
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
	my $username = $c->session('username');
	my $root = path($c->get_user_home, $username);
	my $old_slug = $c->param('catchall');
	my $filename = $c->get_file($old_slug)->to_abs->to_string;
	my $rename_to = $c->param('to');
	my $new_filename = path($root, $rename_to)->to_abs->to_string;
	$c->file->update_file(
		{
			command => 'rename_file',
			username => $username,
			filename => $filename,
			new_filename => $new_filename,
		}
	);
	$c->flash(info => "$old_slug renamed to $rename_to");
	return $c->redirect_to('list_files');
}

sub delete_file {
	my $c = shift;
	my $username = $c->session('username');
	my $slug = $c->param('catchall');
	my $filename = $c->get_file($slug)->to_abs->to_string;
	$c->file->update_file(
		{
			command => 'delete_file',
			username => $username,
			filename => $filename,
		}
	);
	$c->flash(info => "$slug deleted");
	return $c->redirect_to('list_files');
}

sub upload_files {
	my $c = shift;
	my $username = $c->session('username');
	my $root = path($c->get_user_home, $username);
	my @files;
	foreach (@{$c->req->uploads}) {
		my $file = $_->filename;
		if ($_->size > 1024 * 1024 * 50) {
			$c->flash(warning => "File too large");
			$c->res->code(413);
			return $c->redirect_to('list_files');
		}
		my $path = path($root, $file);
		if (-f $path) {
			$c->flash(warning => "$file already exists!");
			$c->res->code(409);
			return $c->redirect_to('list_files');
		};
		$_->move_to($path);
	}
	return $c->redirect_to('list_files');
}

return 1;
