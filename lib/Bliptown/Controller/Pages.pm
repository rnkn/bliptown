package Bliptown::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape sha1_sum);

sub yaml_true {
	my $p = shift;
	if ($p && $p =~ /^(true|y(es)?|1)$/) {
		return 1;
	}
}

sub post_skel {
	my ($html, $slug) = @_;
	$slug =~ s/^\/?/\//;
	my $dom = Mojo::DOM->new($html);
	foreach ($dom->find("a[href=$slug]")->each) {
		my $cur_class = $_->attr('class') // '';
		my @classes = split /\s+/, $cur_class;
		push @classes, 'selected';
		$_->attr(class => join ' ', @classes);

		my $ancestor = $_->parent;
		while ($ancestor) {
			if ($ancestor->type eq 'tag' && $ancestor->tag eq 'details') {
				$ancestor->attr(open => undef);
			}
			$ancestor = $ancestor->parent;
		}
	}
	return $dom->to_string;
}

my @allowed_exts = qw(html css js txt md);

sub render_private {
	my $c = shift;
	my $catchall = $c->param('catchall') || '';
	$c->stash(catchall => 'private/' . $catchall);
	$c->render_page;
}

sub render_page {
	my $c = shift;
	my $user_home = $c->config->{user_home};
	my $req_user = $c->get_req_user;
	my $root = path($user_home, $req_user);
	my $username = $c->session('username');

	my $logpath = path($ENV{BLIPTOWN_LOG_HOME}, $req_user, 'access.log');
	my $logdir = $logpath->dirname;
	$logdir->make_path;
	$c->stash(logpath => $logpath->to_string);

	my $use_cache = $c->param('cache') // 1;
	$c->stash( home => $c->get_home );
	my $user_cur = $username && $username eq $req_user;
	my $slug = $c->stash('catchall');

	unless (-d $root && $root gt $user_home) {
		return $c->reply->not_found;
	}

	my $raw = path($root, $slug);
	my $ext = $raw->extname;
	if ($ext) {
		if (-f $raw) {
			if ($c->app->mode eq 'production' && $ext =~ /jpe?g|png|webp|gif|tiff?/i) {
				return $c->redirect_to("https://cdn.blip.town/$req_user/$slug");
			}
			return $c->reply->file($raw);
		}
		my $fallback = path($c->app->static->paths->[0], 'defaults', $slug);
		return $c->reply->file($fallback) if -f $fallback;
		return $c->reply->not_found;
	}

	$slug = url_unescape($slug);

	my $file;
	if (!$slug || $slug =~ /\/$/) {
		unless ($file = $c->get_file("$slug/index")) {
			$slug =~ s/\/$//;
			if ($file = $c->get_file($slug)) {
				$c->redirect_to('render_page', catchall => $slug);
			}
		};
	} else {
		unless ($file = $c->get_file($slug)) {
			if ($file = $c->get_file("$slug/index")) {
				$c->redirect_to('render_page', catchall => "$slug/");
			}
		}
	}

	if (!$file) {
		if ($user_cur) {
			return $c->redirect_to('new_page', catchall => $slug);
		} else {
			return $c->reply->not_found;
		}
	}

	my $page = $c->page->read_page(
		{
			root => $root,
			file => $file,
		}
	);

	my @skel = qw(header sidebar footer);
	my %skel_html;
	my $show_sidebar = 0;
	foreach (@skel) {
		my $file = path($root, "_$_.md");
		if (-f $file) {
			$show_sidebar = 1 if $_ eq 'sidebar';
			my $page = $c->page->read_page(
				{
					file => $file,
					root => $root,
				}
			);
			$page->{html} = post_skel($page->{html}, $slug);
			$skel_html{$_} = $page->{html};
		}
	}

	my $title_file = path($root, "_title.txt");
	my $title = "Untitled";
	if (-f $title_file) {
		open(my $fh, '<', $title_file);
		$title = <$fh>;
		close($fh);
	}

	my $page_title = $page->{metadata}->{title};
	$title = "$title – $page_title" if $page_title;

	my $date = $page->{metadata}{date};

	my $file_head = path($root, "_head.html");
	my $head = $file_head->slurp('utf-8') if -f $file_head;

	my $show_join = 1
		if $ENV{'BLIPTOWN_JOIN_ENABLED'} == 1 && $req_user eq 'mayor';

	$c->stash(
		template => 'page',
		title => $title,
		head => $head || '',
		show_join => $show_join,
		user_style => 1,
		show_sidebar => $show_sidebar,
		editable => 1,
		header => $skel_html{header} || '',
		menu => $skel_html{sidebar} || '',
		footer => $skel_html{footer} || '',
		content => $page->{html} || '',
		redirect => $c->url_for('render_page'),
	);
	return $c->render;
}

sub backup_page {
	my $c = shift;
	my $username = $c->session('username');
	my $filename = $c->param('catchall');
	my $file = path($c->config->{user_home}, $c->get_req_user, $filename);
	my $redirect = $c->param('back_to') || $c->url_for('list_files');
	my $res = $c->ipc->send_message(
		{
			command => 'backup_file',
			username => $username,
			filename => $file->to_string
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	$c->flash(info => "${filename}~ created");
	return $c->redirect_to($redirect);
}

sub new_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $ext = '';
	if ($slug =~ /(.+)(\..+)$/) {
		 $slug = $1;
		 $ext = $2;
	};
	if ($ext) {
		return $c->reply->not_found unless grep { $ext eq $_} @allowed_exts;
	}
	my $file;
	if (!$slug || $slug =~ /\/$/) {
		unless ($c->get_file("$slug/index")) {
			$slug =~ s/\/$//;
			if ($c->get_file($slug)) {
				return $c->redirect_to('edit_page', catchall => $slug);
			}
		};
	} else {
		if ($c->get_file($slug)) {
			return $c->redirect_to('edit_page', catchall => "$slug");
		} elsif ($c->get_file("$slug/index")) {
			return $c->redirect_to('edit_page', catchall => "$slug/");
		}
	}

	$c->stash(
		template => 'edit',
		title => 'New',
		show_sidebar => 1,
		slug => $slug,
		ext => $ext,
		redirect => $c->url_for('edit_page', catchall => $slug),
	);
	return $c->render;
}

sub edit_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to');
	my $partial_re = qr/^\{\{ *> *(.*?) *\}\}$/;
	my $root = path($c->config->{user_home}, $c->get_req_user);
	my $file;
	if (!$slug || $slug =~ /\/$/) {
		unless ($file = $c->get_file("$slug/index")) {
			$slug =~ s/\/$//;
			if ($file = $c->get_file($slug)) {
				return $c->redirect_to('edit_page', catchall => $slug);
			}
		};
	} else {
		unless ($file = $c->get_file($slug)) {
			if ($file = $c->get_file("$slug/index")) {
				return $c->redirect_to('edit_page', catchall => "$slug/");
			}
		}
	}
	return $c->redirect_to('new_page', catchall => $slug) unless $file;
	my $ext = $c->param('ext') || $file->extname || 'md';
	return $c->reply->not_found unless grep { $ext eq $_} @allowed_exts;
	my $rel_file = $file->to_rel($root); $rel_file =~ s/\.[^.]+?$//;
	my $content;
	my @includes;
	if (-f $file) {
		$content = $c->file->read_file({ file => $file })->{chars};
		my @lines = split /\n/, $content;
		foreach (@lines) {
			if ($_ =~ $partial_re) {
				my $include = $1; $include =~ s/\.[^.]+?$//;
				push @includes, $include;
			}
		}
	}
	$c->stash(
		template => 'edit',
		title => 'Editing ',
		show_sidebar => 1,
		slug => $rel_file,
		ext => $ext,
		filename => $file->basename,
		redirect => $redirect,
		content => $content,
		includes => \@includes,
	);
	return $c->render;
}

sub save_page {
	my $c = shift;
	my $username = $c->session('username');
	my $root = path($c->config->{user_home}, $c->get_req_user)->to_string;
	my $slug = $c->param('slug');
	my $ext = $c->param('ext');
	my $action = $c->param('action');
	my $filename = "$slug.$ext";
	$filename = path($root, $filename)->to_string;
	my $content = $c->param('content');
	$content =~ s/\r\n/\n/g;
	my $user = $c->user->read_user({ key => 'username', username => $username });
	my $backup = $user->{create_backups} // 0;
	my $res = $c->ipc->send_message(
		{
			command => 'update_file',
			username => $username,
			filename => $filename,
			content => $content,
			create_backup => $backup,
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	if ($action eq 'save') {
		return $c->redirect_to($c->url_for('edit_page', catchall => $slug));
	} elsif ($action eq 'save-exit') {
		return $c->redirect_to($c->url_for('render_page', catchall => $slug));
	}
}

sub render_raw {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $file = $c->get_file($slug) || '';
	return $c->reply->not_found unless -f $file;
	my $chars = $file->slurp('utf-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
