package Bliptown::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use POSIX qw(strftime);
use Encode;

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
	my $delete = $c->param('delete');
	my $replace = $c->param('replace');
	my $username = $c->session('username');
	my $user = $c->user->read_user(
		{ key => 'username', username => $username }
	);
	my $root = path($c->config->{user_home}, $username);

	if ($filter && $delete) {
		my $res = delete_files_regex(
			$c, {
				username => $username,
				root => $root,
				filter => $filter
			});
		my $message = $res > 1 ? "$res files deleted" : "$res file deleted";
		$c->flash(info => $message);
		return $c->redirect_to($c->url_for('list_files')->query(filter => $filter));
	}

	if ($filter && defined $replace) {
		rename_files_regex(
			$c, {
				username => $username,
				root => $root,
				filter => $filter,
				replace => $replace
			});
		return $c->redirect_to($c->url_for('list_files')->query(filter => $replace));
	}

	my $tree = $root->list_tree;

	my @files;
	foreach ($tree->each) {
		my $filename = decode('utf-8', $_);
		my @stats = stat($filename);
		my $rel_file = $_->to_rel($root)->to_string;
		my $rel_filename = decode('utf-8', $rel_file);
		my $url = $rel_filename; $url =~ s/\.(md|txt|html|css|js)$//;

		push @files, {
			filename => $rel_filename,
			url => $url,
			size => format_human_size($stats[7]),
			mtime => strftime('%Y-%m-%d %H:%M %z', localtime($stats[9])),
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
		show_sidebar => 1,
		redirect => $c->url_for,
		files => \@files,
	);
	return $c->render;
}

sub rename_files_regex {
	my ($c, $args) = @_;
	my $username = $args->{username};
	my $root =$args->{root};
	my $filter = $args->{filter};
	my $replace = $args->{replace};
	my @files = $root->list_tree->each;
	my @filenames = grep { /$filter/ } map { $_->to_rel($root)->to_string } @files;
	foreach (@filenames) {
		my ($old_filename, $new_filename) = ($_, $_);
		$old_filename = path($root, $old_filename)->to_abs->to_string;
		$new_filename =~ s/$filter/$replace/g;
		$new_filename = path($root, $new_filename)->to_abs->to_string;
		my $res = $c->ipc->send_message(
			{
				command => 'rename_file',
				username => $username,
				filename => $old_filename,
				new_filename => $new_filename,
			}
		);
		return $c->reply->exception($res->{error}) if $res->{error};
	}
	return @filenames;
}

sub rename_file {
	my $c = shift;
	my $username = $c->session('username');
	my $root = path($c->config->{user_home}, $username);
	my $old_slug = $c->param('catchall');
	my $filename = $c->get_file($old_slug)->to_abs->to_string;
	my $rename_to = $c->param('to');
	my $new_filename = path($root, $rename_to)->to_abs->to_string;
	my $res = $c->ipc->send_message(
		{
			command => 'rename_file',
			username => $username,
			filename => $filename,
			new_filename => $new_filename,
		}
	);

	return $c->reply->exception($res->{error}) if $res->{error};

	$c->flash(info => "$old_slug renamed to $rename_to");
	return $c->redirect_to('list_files');
}

sub delete_files_regex {
	my ($c, $args) = @_;
	my $username = $args->{username};
	my $root =$args->{root};
	my $filter = $args->{filter};
	my @files = $root->list_tree->each;
	my @filenames = grep { /$filter/ } map { $_->to_rel($root)->to_string } @files;
	my @filenames_abs = map { path($root, $_)->to_abs->to_string } @filenames;
	foreach (@filenames_abs) {
		my $res = $c->ipc->send_message(
			{
				command => 'delete_file',
				username => $username,
				filename => $_,
			}
		);
		return $c->reply->exception($res->{error}) if $res->{error};
	}
	return @filenames_abs;
}

sub delete_file {
	my $c = shift;
	my $username = $c->session('username');
	my $slug = $c->param('catchall');
	my $filename = path(
		$c->config->{user_home},
		$username,
		$slug
	)->to_abs->to_string;
	my $res = $c->ipc->send_message(
		{
			command => 'delete_file',
			username => $username,
			filename => $filename,
		}
	);

	return $c->reply->exception($res->{error}) if $res->{error};

	$c->flash(info => "$slug deleted");
	return $c->redirect_to('list_files');
}

sub upload_files {
	my $c = shift;
	my $username = $c->session('username');
	my $root = path($c->config->{user_home}, $username);
	foreach (@{$c->req->uploads}) {
		my $filename = $_->filename;
		next unless $filename;
		if ($_->size > 1024 * 1024 * 50) {
			$c->flash(warning => "File too large");
			$c->res->code(413);
			return $c->redirect_to('list_files');
		}
		my $path = path($root, $filename);
		if (-f $path) {
			$c->flash(warning => "$filename already exists!");
			$c->res->code(409);
			return $c->redirect_to('list_files');
		};
		my $blob = $_->slurp;
		my $res = $c->ipc->send_message(
			{
				command => 'write_blob',
				username => $username,
				filename => $path->to_abs->to_string,
				blob => $blob,
			}
		);
		return $c->reply->exception($res->{error}) if $res->{error};
	}
	return $c->redirect_to('list_files');
}

return 1;
