package Bliptown::Controller::Files;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::File qw(path);
use Mojo::Util qw(decode);
use POSIX qw(strftime);
use Text::Glob qw(glob_to_regex_string);

sub list_files {
	my $c = shift;
	my $search = $c->param('search');
	my $delete = $c->param('delete');
	my $replace = $c->param('replace');
	my $sort = $c->param('sort') // 'name';
	my $slug = $c->param('catchall');
	my $username = $c->session('username');
	my $locked = $username eq $ENV{BLIPTOWN_DEMO_USER} ? 1 : 0;
	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username
	});
	my $root = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir = $slug ? path($root, $slug) : $root;
	return $c->reply->not_found unless -d $dir;

	my $search_re = glob_to_regex_string($search) if $search;

	if ($search_re && $delete) {
		my $res = $c->delete_files_regex({
			username => $username,
			dir => $dir,
			search => $search_re,
		});
		my $message = $res > 1 ? "$res files deleted" : "$res file deleted";
		$c->flash(info => $message);
		return $c->redirect_to($c->url_for('list_files')->query(search => $search));
	}

	if ($search_re && defined $replace) {
		my $res = $c->rename_files_regex({
			username => $username,
			dir => $dir,
			search => $search_re,
			replace => $replace
		});
		my $message = $res > 1 ? "$res files renamed" : "$res file renamed";
		$c->flash(info => $message);
		return $c->redirect_to($c->url_for('list_files')->query(search => $replace));
	}

	my @files;
	my $max_depth = $search_re ? undef : 1;
	my $tree = $dir->list_tree({ dir => 1, max_depth => $max_depth });
	foreach my $file (@$tree) {
		my $filename = decode('utf-8', $file);
		my @stats = stat($filename);
		my $rel_root_filename = decode('utf-8', $file->to_rel($root)->to_string);
		my $rel_dir_filename = decode('utf-8', $file->to_rel($dir)->to_string);
		my $is_dir = -d $filename;
		my $exts_re = join '|', @{$c->config->{render_exts}};
		my $url = $rel_root_filename =~ s/\.($exts_re)$//r;

		push @files, {
			abs_filename => $rel_root_filename,
			rel_filename => $rel_dir_filename,
			is_dir => $is_dir,
			url => $url,
			size => $stats[7],
			mtime => $stats[9],
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
	unless ($dir eq $root) {
		my @breadcrumb_dirs = @{$dir->to_rel($root)};

		while (@breadcrumb_dirs) {
			my $path = join '/', @breadcrumb_dirs;
			my $name = pop @breadcrumb_dirs;
			my %crumb = (
				name => $name,
				path => $path,
			);
			push @breadcrumbs, \%crumb;
		}
		@breadcrumbs = reverse @breadcrumbs;
	}

	$c->stash(
		template => 'files',
		title => 'Files',
		locked => $locked,
		redirect => $c->url_for,
		breadcrumbs => \@breadcrumbs,
		files => \@files,
	);
	return $c->render;
}

sub file_action {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $action = $c->param('action');

	if ($action eq 'new_directory') {
		my $name = $c->param('name');
		return $c->new_directory($slug, $name);
	}
}

sub new_directory {
	my ($c, $slug, $name) = @_;
	my $username = $c->session('username');
	my $rel_dir = $slug ? join '/', ($slug, $name) : $name;
	my $dir = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $rel_dir);
	my $redirect = $c->url_for('list_files', catchall => $rel_dir);
	return $c->redirect_to($redirect) if -d $dir;

	my $res = $c->ipc->send_message({
		command => 'make_directory',
		system_user => $username,
		filename => $dir->to_string,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	$c->flash(info => "Created directory $name");
	return $c->redirect_to($redirect);
}

sub rename_files_regex {
	my ($c, $args) = @_;
	my $username = $args->{username};
	my $dir = $args->{dir};
	my $search = $args->{search};
	my $replace = $args->{replace};
	my @files = $dir->list_tree({ dir => 1 })->each;
	my @filenames = grep { /$search/ } map { $_->to_rel($dir)->to_string } @files;
	my @filenames_abs = map { path($dir, $_)->to_abs->to_string } @filenames;
	@filenames_abs = sort { length $b <=> length $a } @filenames_abs;
	foreach my $filename (@filenames) {
		my ($old_filename, $new_filename) = ($filename, $filename);
		$old_filename = path($dir, $old_filename)->to_abs->to_string;
		$new_filename =~ s/$search/$replace/g;
		$new_filename = path($dir, $new_filename)->to_abs->to_string;
		my $res = $c->ipc->send_message({
			command => 'rename_file',
			system_user => $username,
			filename => $old_filename,
			new_filename => $new_filename,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info}) unless $c->app->mode eq 'production';
	}
	return @filenames;
}

sub rename_file {
	my $c = shift;
	my $username = $c->session('username');
	my $redirect = $c->param('back_to')
		// $c->url_for('list_files', catchall => '');
	my $root = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $slug = $c->param('catchall');
	my $file = path($root, $slug);
	my $filename = $file->to_abs->to_string;
	return $c->reply->not_found unless -e $file;
	my $rename_to = $c->param('name');
	my $new_filename = path($root, $rename_to)->to_abs->to_string;

	if (-d $filename && $new_filename =~ m{^$filename(/|$)}) {
		$c->flash(info => "Cannot move $slug into itself!");
		return $c->redirect_to($redirect);
	}

	my $res = $c->ipc->send_message({
		command => 'rename_file',
		system_user => $username,
		filename => $filename,
		new_filename => $new_filename,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $message;
	if (-d $filename) {
		$message = "Directory $slug renamed to $rename_to";
	} else {
		$message = "File $slug renamed to $rename_to"
	}
	$c->flash(info => $message);
	return $c->redirect_to($redirect);
}

sub delete_files_regex {
	my ($c, $args) = @_;
	my $username = $args->{username};
	my $dir =$args->{dir};
	my $search = $args->{search};
	my @files = $dir->list_tree({ dir => 1 })->each;
	my @filenames = grep { /$search/ } map { $_->to_rel($dir)->to_string } @files;
	my @filenames_abs = map { path($dir, $_)->to_abs->to_string } @filenames;
	@filenames_abs = sort { length $b <=> length $a } @filenames_abs;
	foreach my $filename (@filenames_abs) {
		my $res = $c->ipc->send_message({
			command => 'delete_file',
			system_user => $username,
			filename => $filename,
		});
		return $c->reply->exception($res->{error}) if $res->{error};
		$c->log->debug($res->{info}) unless $c->app->mode eq 'production';
	}
	return @filenames_abs;
}

sub delete_file {
	my $c = shift;
	my $username = $c->session('username');
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to')
		// $c->url_for('list_files', catchall => '');
	my $file = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $slug)->to_abs;
	if (-d $file && @{$file->list({ dir => 1 })} > 0) {
		$c->flash(info => "Directory $slug not empty!");
		return $c->redirect_to($redirect);
	}
	my $res = $c->ipc->send_message({
		command => 'delete_file',
		system_user => $username,
		filename => $file->to_string,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	$c->flash(info => "File $slug deleted");
	return $c->redirect_to($redirect);
}

sub backup_file {
	my $c = shift;
	my $username = $c->session('username');
	my $filename = $c->param('catchall');
	my $file = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, $filename);
	return $c->reply->not_found unless -f $file;
	my $redirect = $c->param('back_to') // $c->url_for('list_files');
	my $res = $c->ipc->send_message({
		command => 'backup_file',
		system_user => $username,
		filename => $file->to_string
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
	my $root = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
	my $dir = $slug ? path($root, $slug) : $root;
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
			my $cdn_url = "https://cdn.blip.town/$username/$slug/$filename";
			my $res = $c->file->purge_cdn_file({ url => $cdn_url });
			$c->log->error("CDN Purge failed: $cdn_url") unless $res->code == 200;
		}
	}
	return $c->redirect_to('list_files');
}

return 1;
