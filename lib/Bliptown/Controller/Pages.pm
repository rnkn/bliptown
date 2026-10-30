package Bliptown::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller';
use YAML::Tiny;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape decode);
use Text::Glob qw(glob_to_regex_string);
use List::Util qw(any);

sub process_redirects {
	my ($path, $slug) = @_;
	$slug =~ s{^/?}{/};
	$slug =~ s{/?$}{};
	my $chars = $path->slurp('UTF-8');
	my $y = YAML::Tiny->new;
	my $redirects = eval { $y->read_string($chars)->[0] };

	foreach my $glob (keys %$redirects) {
		my $re = glob_to_regex_string($glob);
		if ($slug =~ qr/$re/) {
			my $url = $redirects->{$glob};
			return $url;
		}
	}
	return;
}

sub postprocess_skel {
	my ($html, $slug) = @_;
	$slug =~ s{^/?}{/};
	my $url_path = Mojo::URL->new($slug)->to_string;
	$url_path =~ s{/$}{};
	my $dom = Mojo::DOM->new($html);
	my @links = @{$dom->find("a[href=\"$url_path\"]")};
	foreach my $link (@links) {
		my $cur_class = $link->attr('class') // '';
		my @classes = split /\s+/, $cur_class;
		push @classes, 'selected';
		$link->attr(class => join ' ', @classes);

		my $ancestor = $link->parent;
		while ($ancestor) {
			if ($ancestor->type eq 'tag' && $ancestor->tag eq 'details') {
				$ancestor->attr(open => undef);
			}
			$ancestor = $ancestor->parent;
		}
	}
	return $dom->to_string;
}

sub render_style {
	my $c = shift;
	my $theme = $c->param('theme');
	my $path;
	if ($theme) {
		$path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $ENV{BLIPTOWN_THEME_USER}, "$theme.css");
	}
	else {
		$path = path($c->get_req_user_path, 'style.css');
	}
	if (-f $path) {
		return $c->reply->file($path);
	}
	return $c->reply->not_found;
}

sub render_page {
	my $c = shift;
	my $req_username = $c->get_req_username;
	return $c->reply->not_found unless $req_username;
	my $user_path = $c->get_req_user_path;
	my $username = $c->session('username');

	my $is_cur_user = $username && $username eq $req_username;

	my $slug = url_unescape $c->param('catchall');
	my $prefix = $c->stash('prefix');
	$slug = "$prefix/" . $slug if $prefix;

	my $redirects_path = path($user_path, '_redirects.txt');
	my $redirect_url = process_redirects($redirects_path, $slug)
		if -f $redirects_path;
	return $c->redirect_to($redirect_url) if $redirect_url;

	my $file = $c->get_file($slug, 1);

	if ($file && (my $ext = $file->extname)) {
		my $cached = $c->app->config->{cdn_exts}->{$ext};
		if ($c->app->mode eq 'production' && $cached) {
			return $c->redirect_to("https://cdn.blip.town/$req_username/$slug");
		}
		return $c->reply->file($file);
	}

	if (!$slug || $slug =~ m{/$}) {
		$file = $c->get_file("$slug/index");
		if (!$file) {
			$slug =~ s{/$}{};
			$file = $c->get_file($slug);
			return $c->redirect_to('render_page', catchall => $slug) if $file;
		}
	}
	else {
		$file = $c->get_file($slug);
		if (!$file) {
			$file = $c->get_file("$slug/index");
			return $c->redirect_to('render_page', catchall => "$slug/") if $file;
		}
	}

	if (!$file) {
		if ($is_cur_user) {
			return $c->redirect_to('new_page', catchall => $slug);
		} else {
			return $c->reply->not_found;
		}
	}

	if (${$file}[-1] eq 'index.html') {
		return $c->reply->file($file);
	}

	my $page = $c->page->read_page({
		filename => $file->to_abs->to_string,
	});

	my @skel = qw(header menu footer);
	my %skel_html;
	foreach my $f (@skel) {
		my $skel_path = path($user_path, "_$f.md");
		if (-f $skel_path) {
			my $skel_page = $c->page->read_page({
				filename => $skel_path->to_abs->to_string,
			});
			$skel_page->{html} = postprocess_skel($skel_page->{html}, $slug);
			$skel_html{$f} = $skel_page->{html};
		}
	}

	my $site_title = $c->util->read_file_line(path($user_path, '_title.txt'))
		|| $c->app->defaults('site_title');

	my $page_title = $page->{metadata}->{title}
		|| $c->app->defaults('page_title');

	my $author = $c->util->read_file_line(path($user_path, '_author.txt'))
		|| $c->app->defaults('author');

	my $desc = $c->app->defaults('description');
	my $desc_path = path($user_path, '_description.txt');
	if (-f $desc_path) {
		my $desc_chars = $desc_path->slurp('UTF-8');
		$desc = join ' ', split /\n/, $desc_chars;
	}

	my $scripts_path = path($user_path, 'scripts');
	my @scripts = $scripts_path->list_tree->each if -d $scripts_path;
	@scripts = map { '/' . $_->to_rel($user_path)->to_string } grep { $_->extname eq 'js' } @scripts;

	$c->stash(
		template	=> 'page',
		site_title	=> $site_title,
		page_title	=> $page_title,
		description	=> $desc,
		author		=> $author,
		scripts		=> \@scripts,
		theme		=> $c->param('theme')	// '',
		customize	=> 1,
		editable	=> 1,
		header		=> $skel_html{header}	// '',
		menu		=> $skel_html{menu}		// '',
		footer		=> $skel_html{footer}	// '',
		content		=> $page->{html}		// '',
		redirect	=> $c->url_for('render_page'),
	);
	return $c->render;
}

sub new_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $ext = $c->param('ext') || 'md';
	if ($slug =~ /(.+)\.([^.]+)$/) {
		 $slug = $1;
		 $ext = $2;
	};
	return $c->reply->not_found unless any { $ext eq $_} @{$c->app->config->{render_exts}};

	if (!$slug || $slug =~ m{/$}) {
		unless ($c->get_file("$slug/index")) {
			$slug =~ s{/$}{};
			if ($c->get_file($slug)) {
				return $c->redirect_to('edit_page', catchall => $slug);
			}
		}
	} else {
		if ($c->get_file($slug)) {
			return $c->redirect_to('edit_page', catchall => "$slug");
		}
		elsif ($c->get_file("$slug/index")) {
			return $c->redirect_to('edit_page', catchall => "$slug/");
		}
	}

	my $content;
	if ($ext eq 'md') {
		my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $c->session('username'))->to_abs;
		my $search_path = path($user_path, $slug);
		$content = $c->util->get_template($search_path);
	}

	$c->stash(
		template => 'edit',
		page_title => 'New',
		slug => $slug,
		ext => $ext,
		content => $content,
		redirect => $c->url_for('edit_page', catchall => $slug),
	);
	return $c->render;
}

sub edit_page {
	my $c = shift;
	my $username = $c->session('username');
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to');
	my $partial_re = qr/^\{\{ *> *(.*?) *\}\}$/;
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->realpath;
	my $path;
	if (!$slug || $slug =~ m{/$}) {
		unless ($path = $c->get_file("$slug/index")) {
			$slug =~ s{/$}{};
			if ($path = $c->get_file($slug)) {
				return $c->redirect_to('edit_page', catchall => $slug);
			}
		};
	} else {
		unless ($path = $c->get_file($slug)) {
			if ($path = $c->get_file("$slug/index")) {
				return $c->redirect_to('edit_page', catchall => "$slug/");
			}
		}
	}
	return $c->redirect_to('new_page', catchall => $slug) unless -f $path;
	my $ext = $c->param('ext') || $path->extname || 'md';
	return $c->reply->not_found unless grep { $ext eq $_} @{$c->app->config->{render_exts}};
	my $rel_filename = $path->to_rel($user_path)->to_string;
	$rel_filename = decode('UTF-8', $rel_filename);
	my $basename = $rel_filename =~ s/\.[^.]+?$//r;
	my $content;
	my @includes;
	if (-f $path) {
		$content = $c->file->read_file({ filename => $path->to_string })->{chars};
		my @lines = split /\n/, $content;
		foreach my $line (@lines) {
			if ($line =~ $partial_re) {
				my $include = $1;
				foreach my $f ($c->util->glob_path($include, $path->to_string)) {
					$f = path($f)->to_rel($user_path);
					push @includes, $f;
				}
			}
		}
	}
	$c->stash(
		template => 'edit',
		page_title => 'Editing ',
		slug => $basename,
		ext => $ext,
		redirect => $redirect,
		content => $content,
		includes => \@includes,
	);
	return $c->render;
}

sub save_page {
	my $c = shift;
	my $username = $c->session('username');
	my $user_path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username)->to_abs;
	my $slug = $c->param('slug');
	$slug =~ s{^/}{};
	my $ext = $c->param('ext');
	my $path = path($user_path, "$slug.$ext");
	my $content = $c->param('content');
	my $redirect = $c->param('back_to');
	$content =~ s/\r\n/\n/g;

	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username
	});
	my $backup = $user_rec->{create_backups} // 0;

	my $res = $c->ipc->send_message({
		command => 'update_file',
		system_user => $username,
		filenames => [ $path->to_string ],
		content => $content,
		create_backup => $backup,
	});
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info});

	return $c->redirect_to($c->url_for('edit_page', catchall => $slug)->query(back_to => $redirect));
}

sub render_raw {
	my $c = shift;
	my $slug = url_unescape $c->param('catchall');
	my $prefix = $c->stash('prefix');
	$slug = "$prefix/" . $slug if $prefix;

	my $path = $c->get_file($slug);
	return $c->reply->txt_not_found unless $path;
	my $chars = $path->slurp('UTF-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
