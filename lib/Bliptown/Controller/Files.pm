package Bliptown::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use Mojo::Util qw(decode);
use POSIX qw(strftime);
use Text::Glob qw(glob_to_regex_string);

sub new_file {
	my $c = shift;
	my $basename = $c->param('name');
	my $ext = $c->param('ext');
	my $dir = $c->param('dir');
	my $redirect = $c->param('back_to') // $c->url_for('list_files');
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $c->session('username'));

	my $path = path($user_path, $dir, "$basename.$ext")->touch;
	return $c->redirect_to($redirect);
}

sub list_files {
	my $c = shift;
	my $username = $c->session('username');
	my $search = $c->param('search');
	my $sort = $c->param('sort') // 'name';
	my $slug = $c->param('catchall');
	my $locked = $username eq $ENV{BLIPTOWN_DEMO_USER} ? 1 : 0;
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir_path = $slug ? path($user_path, $slug) : $user_path;
	return $c->reply->not_found unless -d $dir_path;

	my $search_re = glob_to_regex_string($search) if $search;

	my @files;
	my $max_depth = $search_re ? undef : 1;
	my @tree = $dir_path->list_tree({ dir => 1, max_depth => $max_depth })->each;
	foreach my $path (@tree) {
		my $stats = $path->stat;
		my $filename = decode('UTF-8', $path->to_string);
		my $filename_rel_user_path = decode('UTF-8', $path->to_rel($user_path)->to_string);
		my $filename_rel_dir_path = decode('UTF-8', $path->to_rel($dir_path)->to_string);
		my $is_dir = -d $filename;
		my $exts_re = join '|', @{$c->app->config->{render_exts}};
		my $url = $filename_rel_user_path =~ s/\.($exts_re)$//r;

		push @files, {
			abs_filename => $filename_rel_user_path,
			rel_filename => $filename_rel_dir_path,
			is_dir => $is_dir,
			url => $url,
			size => $stats->size,
			mtime => $stats->mtime,
		}
	};

	@files = grep { $_->{rel_filename} =~ $search_re } @files if $search_re;

	my %sorting = (
		name => 'rel_filename',
		size => 'size',
		date => 'mtime'
	);

	my $key = $sorting{$sort};
	if ($key eq 'mtime') {
		@files = sort { $b->{$key} cmp $a->{$key} } @files;
	} elsif ($key eq 'size') {
		@files = sort { $b->{$key} <=> $a->{$key} } @files;
	} else {
		@files = sort { $a->{$key} cmp $b->{$key} } @files;
	}

	foreach my $file (@files) {
		$file->{size} = $c->util->format_human_size($file->{size});
		$file->{mtime} = strftime('%Y-%m-%d %H:%M %z', localtime($file->{mtime}));
	}

	my @breadcrumbs;
	unless ($dir_path eq $user_path) {
		my @breadcrumb_dirs = @{$dir_path->to_rel($user_path)};

		while (@breadcrumb_dirs) {
			my $path_to_string = join '/', @breadcrumb_dirs;
			my $dirname = pop @breadcrumb_dirs;
			my %crumb = (
				dirname => $dirname,
				path => $path_to_string,
			);
			push @breadcrumbs, \%crumb;
		}
		@breadcrumbs = reverse @breadcrumbs;
	}

	$c->stash(
		template => 'files',
		page_title => 'Files',
		locked => $locked,
		dir => $slug,
		redirect => $c->url_for,
		breadcrumbs => \@breadcrumbs,
		files => \@files,
	);
	return $c->render;
}

sub new_directory {
	my $c = shift;
	my $dir = $c->param('dir') // '';
	my $name = $c->param('name');
	my $username = $c->session('username');
	my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $dir, $name);
	my $rel_path = $path->to_rel($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $redirect = $c->url_for('list_files', catchall => $rel_path);
	return $c->redirect_to($redirect) if -d $path;

	my $res = $c->ipc->send_message({
		command => 'make_directory',
		system_user => $username,
		filename => $path->to_string,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	$c->flash(info => "Created directory $name");
	return $c->redirect_to($redirect);
}

sub rename_files {
	my $c = shift;
	my $username = $c->session('username');
	my $dir = $c->param('dir') // '';
	my $filename = $c->param('filename');
	my $new_filename = $c->param('new_filename');
	my $search = $c->param('search');
	my $replace = $c->param('replace');
	my $redirect = $c->param('back_to') // $c->url_for('list_files');
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);

	my %filename_pairs;
	if ($search) {
		return $c->reply->not_found unless $replace;

		my $search_re = glob_to_regex_string($search);
		my $dir_path = path($user_path, $dir);
		return $c->reply->not_found unless -d $dir_path;

		my @tree = $dir_path->list_tree({ dir => 1 })->each;
		my @old_rel_paths = grep { /$search_re/ } map { $_->to_rel($dir_path) } @tree;

		foreach my $old_rel (@old_rel_paths) {
			my $new_rel = $old_rel =~ s/$search_re/$replace/gr;
			my $old_abs = path($dir_path, $old_rel)->to_abs->to_string;
			my $new_abs = path($dir_path, $new_rel)->to_abs->to_string;
			$filename_pairs{$old_abs} = $new_abs;
		}
	}
	else {
		my $old_abs_path = path($user_path, $filename)->to_abs;
		return $c->reply->not_found unless -e $old_abs_path;

		my $new_abs_path = path($user_path, $new_filename)->to_abs;

		if (-d $new_abs_path && $new_abs_path =~ m{^\Q$old_abs_path\E(/|$)}) {
			$c->flash(info => "Cannot move $filename into itself!");
			return $c->redirect_to($redirect);
		}

		$filename_pairs{$old_abs_path->to_string} = $new_abs_path->to_string;
	}

	foreach my $old_abs (sort { length $b <=> length $a } keys %filename_pairs) {
		my $res = $c->ipc->send_message({
			command => 'rename_file',
			system_user => $username,
			filename => $old_abs,
			new_filename => $filename_pairs{$old_abs},
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info}) unless $c->app->mode eq 'production';
	}

	my $count = keys %filename_pairs;
	my $message = $count > 1 ? "$count files renamed" : "$count file renamed";
	$c->flash(info => $message);
	return $c->redirect_to($redirect);
}

sub delete_files {
	my $c = shift;
	my $username = $c->session('username');
	my $dir = $c->param('dir') // '';
	my $filename = $c->param('filename') // '';
	my $search = $c->param('search');
	my $redirect = $c->param('back_to') // $c->url_for('list_files');
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);

	my @filenames_abs;
	if ($search) {
		my $search_re = glob_to_regex_string($search);
		my $dir_path = path($user_path, $dir);
		my @tree = $dir_path->list_tree({ dir => 1 })->each;
		my @filenames = grep { /$search_re/ } map { $_->to_rel($dir_path)->to_string } @tree;
		@filenames_abs = map { path($dir_path, $_)->to_abs->to_string } @filenames;
		@filenames_abs = sort { length $b <=> length $a } @filenames_abs;
	}
	else {
		my $path = path($user_path, $filename)->to_abs;
		if (-d $path && @{$path->list({ dir => 1 })} > 0) {
			$c->flash(info => "Directory $filename not empty!");
			return $c->redirect_to($redirect);
		}
		@filenames_abs = ($path->to_string);
	}

	foreach my $filename (@filenames_abs) {
		my $res = $c->ipc->send_message({
			command => 'delete_file',
			system_user => $username,
			filename => $filename,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info}) unless $c->app->mode eq 'production';
	}

	my $count = @filenames_abs;
	my $message = $count > 1 ? "$count files deleted" : "$count file deleted";
	$c->flash(info => $message);
	return $c->redirect_to($redirect);
}

sub backup_file {
	my $c = shift;
	my $username = $c->session('username');
	my $filename = $c->param('filename');
	my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $filename);
	return $c->reply->not_found unless -f $path;
	my $redirect = $c->param('back_to') // $c->url_for('list_files');

	my $res = $c->ipc->send_message({
		command => 'backup_file',
		system_user => $username,
		filename => $path->to_string,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	$c->flash(info => "File ${filename}~ created");
	return $c->redirect_to($redirect);
}

sub upload_files {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to')
		// $c->url_for('list_files', catchall => '');
	my $username = $c->session('username');
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir = $slug ? path($user_path, $slug) : $user_path;
	foreach my $upload (@{$c->req->uploads}) {
		my $filename = $upload->filename;
		next unless $filename;
		my $path = path($dir, $filename);
		if (-f $path) {
			$c->flash(info => "File $filename exists!");
			$c->res->code(409);
			return $c->redirect_to('list_files');
		};
		my $blob = $upload->slurp;
		my $res = $c->ipc->send_message({
			command => 'write_blob',
			system_user => $username,
			filename => $path->to_abs->to_string,
			blob => $blob,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

		if ($c->app->mode eq 'production') {
			my $res = $c->file->purge_cdn_file({
				path => $path->to_abs->to_string,
			});
			$c->log->error("CDN Purge failed: $path") unless $res->code == 200;
		}
	}
	return $c->redirect_to('list_files');
}

return 1;
