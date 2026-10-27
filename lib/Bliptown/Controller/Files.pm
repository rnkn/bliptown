package Bliptown::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use Mojo::Util qw(encode decode);
use POSIX qw(strftime);
use Text::Glob qw(glob_to_regex_string);

sub new_file {
	my $c = shift;
	my $username = $c->session('username');
	my $name = $c->param('name');
	my $ext = $c->param('ext');
	my $dir = $c->param('dir');
	my $basename = path($name)->basename;
	my $dir_path = path($dir, $name)->dirname // '';
	my $redirect = $c->param('back_to') // $c->url_for('list_files');

	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->to_abs;
	$dir_path = path($user_path, $dir_path);

	unless (-d $dir_path) {
		my $res = $c->ipc->send_message({
			command => 'make_directory',
			system_user => $username,
			filename => $dir_path->to_string,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info});
	}

	my $path = path($dir_path, "$basename.$ext");
	my $content = $ext eq 'md' ? $c->util->get_template($dir_path) : '';

	my $res = $c->ipc->send_message({
		command => 'update_file',
		system_user => $username,
		filename => $path->to_string,
		content => $content,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

	return $c->redirect_to($redirect);
}

sub list_files {
	my $c = shift;
	my $username = $c->session('username');
	my $search = $c->param('search');
	my $sort = $c->param('sort') // 'name';
	my $dir = $c->param('catchall') // '';
	my $locked = $username eq $ENV{BLIPTOWN_DEMO_USER} ? 1 : 0;
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir_path = $dir ? path($user_path, encode('UTF-8', $dir)) : $user_path;
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
		dir => $dir,
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
	my $rel_path = path($dir, $name);
	my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $rel_path)->to_abs;
	my $redirect = $c->url_for('list_files', catchall => $rel_path);
	return $c->redirect_to($redirect) if -d $path;

	my $res = $c->ipc->send_message({
		command => 'make_directory',
		system_user => $username,
		filename => $path->to_string,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

	$c->flash(info => "Created directory $name");
	return $c->redirect_to($redirect);
}

sub rename_files {
	my $c = shift;
	my $username = $c->session('username');
	my $dir = $c->param('dir') // '';
	my $old = $c->param('old');
	return $c->reply->not_found unless $old;
	my $new = $c->param('new') // '';
	my $redirect = $c->url_for('list_files')->query(search => $c->param('new'));

	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir_path = path($user_path, $dir);
	return $c->reply->not_found unless -d $dir_path;

	my $search_re = glob_to_regex_string($old);
	my @tree = $dir_path->list_tree({ dir => 1 })->each;
	my @old_rel_paths = grep { /$search_re/ } map { $_->to_rel($dir_path)->to_string } @tree;
	return $c->reply->not_found unless @old_rel_paths;

	my @rename_pairs;
	foreach my $old_rel (@old_rel_paths) {
		my $old_abs = path($dir_path, $old_rel)->to_abs->to_string;
		my $new_rel = $old_rel =~ s/$search_re/$new/gr;
		my $new_abs = path($dir_path, $new_rel)->to_abs->to_string;
		if (-d $new_abs && $new_abs =~ m{^\Q$old_abs\E(/|$)}) {
			$c->flash(info => "Cannot move $old into itself!");
			return $c->redirect_to($redirect);
		}
		push @rename_pairs, {
			old => $old_abs,
			new => $new_abs,
		}
	}

	@rename_pairs = sort { length $b->{old} <=> length $a->{old} } @rename_pairs;

	my $res = $c->ipc->send_message({
		command => 'rename_files',
		system_user => $username,
		filenames => \@rename_pairs,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

	my $count = scalar @rename_pairs;
	my $message = $count > 1 ? "$count files renamed" : "$count file renamed";
	$c->flash(info => $message);
	return $c->redirect_to($redirect);
}

sub delete_files {
	my $c = shift;
	my $username = $c->session('username');
	my $dir = $c->param('dir') // '';
	my $filenames = $c->param('filenames');
	return $c->reply->not_found unless $filenames;
	my $redirect = $c->param('back_to') // $c->url_for('list_files', catchall => $dir)->query(search => $filenames);

	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir_path = path($user_path, $dir);
	return $c->reply->not_found unless -d $dir_path;

	my $search_re = glob_to_regex_string($filenames);
	my @tree = $dir_path->list_tree({ dir => 1 })->each;
	my @rel_paths = grep { /$search_re/ } map { $_->to_rel($dir_path)->to_string } @tree;
	return $c->reply->not_found unless @rel_paths;

	my @filenames_abs;
	foreach my $rel_path (@rel_paths) {
		my $filename_abs = path($dir_path, $rel_path)->to_abs->to_string;
		push @filenames_abs, $filename_abs;
	}

	my $res = $c->ipc->send_message({
		command => 'delete_files',
		system_user => $username,
		filenames => \@filenames_abs,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

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
	$c->log->debug($res->{info});

	$c->flash(info => "File ${filename}~ created");
	return $c->redirect_to($redirect);
}

sub upload_files {
	my $c = shift;
	my $username = $c->session('username');
	my $dir = $c->param('dir') // '';
	my $redirect = $c->param('back_to')
		// $c->url_for('list_files', catchall => '');

	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir_path = path($user_path, $dir);

	foreach my $upload (@{$c->req->uploads}) {
		my $filename = $upload->filename;
		next unless $filename;
		my $path = path($dir_path, $filename);
		if (-f $path) {
			$c->flash(info => "File $filename exists!");
			$c->res->code(409);
			return $c->redirect_to($redirect);
		};
		my $blob = $upload->slurp;
		my $res = $c->ipc->send_message({
			command => 'write_blob',
			system_user => $username,
			filename => $path->to_abs->to_string,
			blob => $blob,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info});

		if ($c->app->mode eq 'production') {
			my $res = $c->file->purge_cdn_file({
				filename => $path->to_abs->to_string,
			});
			$c->log->error("CDN Purge failed: $path") unless $res->code == 200;
		}
	}
	return $c->redirect_to($redirect);
}

sub download_site {
	my $c = shift;
	my $username = $c->session('username');
	my $res = $c->ipc->send_message({
		command => 'download_site',
		system_user => $username,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

	my $filename = $res->{info};
	my $asset = Mojo::Asset::File->new(path => $filename);

	$c->res->headers->content_type('application/gzip');
	$c->res->headers->content_disposition(
		"attachment; filename=${username}.$ENV{BLIPTOWN_DOMAIN}.tar.gz"
	);

	$c->on(
		finish => sub {
			my $res = $c->ipc->send_message({
				command => 'delete_files',
				system_user => $username,
				filenames => [ $filename ],
			});
			return $c->log->error($res->{error}) if $res->{error};
			$c->log->debug($res->{info});
		});

	return $c->reply->asset($asset);
}

return 1;
