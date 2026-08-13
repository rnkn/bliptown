package Bliptown::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller';
use YAML::Tiny;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape);
use Text::Glob qw(glob_to_regex_string);

sub process_redirects {
	my ($file, $slug) = @_;
	$slug =~ s{^/?}{/};
	$slug =~ s{/?$}{};
	my $chars = $file->slurp('utf-8');
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
	foreach my $link (@{$dom->find("a[href=\"$url_path\"]")}) {
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
	my $req_user = $theme ? 'demo' : $c->get_req_user;
	my $root = path($ENV{BLIPTOWN_USER_HOME}, $req_user);
	my $file;
	if ($theme) {
		$file = path($root, "$theme.css");
	}
	else {
		$file = path($root, 'style.css');
	}
	if (-f $file) {
		return $c->reply->file($file);
	}
	return $c->reply->not_found;
}

sub render_page {
	my $c = shift;
	my $req_user = $c->get_req_user;
	return $c->reply->not_found unless $req_user;
	my $root = path($ENV{BLIPTOWN_USER_HOME}, $req_user);
	my $username = $c->session('username');

	my $is_cur_user = $username && $username eq $req_user;

	my $slug = url_unescape $c->param('catchall');
	my $subdir = $c->stash('subdir');
	$slug = "$subdir/" . $slug if $subdir;

	my $redirects_file = path($root, '_redirects.txt');
	my $redirect_url = process_redirects($redirects_file, $slug)
		if -f $redirects_file;
	return $c->redirect_to($redirect_url) if $redirect_url;

	my $raw = path($root, $slug);
	my $ext = $raw->extname;
	if ($ext) {
		if (-f $raw) {
			my @cached = grep { $ext eq $_ } @{$c->app->config->{cdn_exts}};
			if ($c->app->mode eq 'production' && @cached) {
				return $c->redirect_to("https://cdn.blip.town/$req_user/$slug");
			}
			return $c->reply->file($raw);
		}
		my $fallback = path($c->app->static->paths->[0], 'defaults', $slug);
		return $c->reply->file($fallback) if -f $fallback;
	}

	my $file;
	if (!$slug || $slug =~ m{/$}) {
		unless ($file = $c->get_file("$slug/index")) {
			$slug =~ s{/$}{};
			if ($file = $c->get_file($slug)) {
				return $c->redirect_to('render_page', catchall => $slug);
			}
		};
	} else {
		unless ($file = $c->get_file($slug)) {
			if ($file = $c->get_file("$slug/index")) {
				return $c->redirect_to('render_page', catchall => "$slug/");
			}
		}
	}

	if (!$file) {
		if ($is_cur_user) {
			return $c->redirect_to('new_page', catchall => $slug);
		} else {
			return $c->reply->not_found;
		}
	}

	if ($$file[-1] eq 'index.html') {
		return $c->reply->file($file);
	}

	my $page = $c->page->read_page({
		root => $root->to_abs->to_string,
		filename => $file->to_abs->to_string,
	});

	my @skel = qw(header menu footer);
	my %skel_html;
	foreach my $f (@skel) {
		my $file = path($root, "_$f.md");
		if (-f $file) {
			my $page = $c->page->read_page({
				filename => $file->to_abs->to_string,
				root => $root->to_abs->to_string,
			});
			$page->{html} = postprocess_skel($page->{html}, $slug);
			$skel_html{$f} = $page->{html};
		}
	}

	my $title_file = path($root, "_title.txt");
	my $title = "Untitled";
	if (-s $title_file) {
		open(my $fh, '<', $title_file);
		$title = <$fh>;
		close($fh);
	}

	my $page_title = $page->{metadata}->{title};
	$title = "$title – $page_title" if $page_title;

	$c->stash(
		template => 'page',
		title => $title,
		user_style => 1,
		theme => $c->param('theme'),
		editable => 1,
		header => $skel_html{header} || '',
		menu => $skel_html{menu} || '',
		footer => $skel_html{footer} || '',
		content => $page->{html} || '',
		redirect => $c->url_for('render_page'),
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
	return $c->reply->not_found unless grep { $ext eq $_} @{$c->config->{render_exts}};

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

	my ($template, $content);
	if ($ext eq 'md') {
		my $root = path($ENV{BLIPTOWN_USER_HOME}, $c->session('username'))->to_abs;
		my $path = path($root, $slug)->to_abs;

		while (1) {
			my $candidate = $path->child('_template.md');
			if (-f $candidate) {
				$template = $candidate;
				last;
			}
			last if $path le $root;
			$path = $path->dirname;
		}

		$content = $template->slurp('utf-8') if $template;
	}

	$c->stash(
		template => 'edit',
		title => 'New',
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
	my $root = path($ENV{BLIPTOWN_USER_HOME}, $username);
	my $file;
	if (!$slug || $slug =~ m{/$}) {
		unless ($file = $c->get_file("$slug/index")) {
			$slug =~ s{/$}{};
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
	return $c->reply->not_found unless grep { $ext eq $_} @{$c->config->{render_exts}};
	my $rel_file = $file->to_rel($root); $rel_file =~ s/\.[^.]+?$//;
	my $content;
	my @includes;
	if (-f $file) {
		$content = $c->file->read_file({ file => $file })->{chars};
		my @lines = split /\n/, $content;
		foreach my $line (@lines) {
			if ($line =~ $partial_re) {
				my $include = $1;
				foreach my $f ($c->util->glob_path($include, $root, $file)) {
					$f = Mojo::File->new($f)->to_rel($root);
					push @includes, $f;
				}
			}
		}
	}
	$c->stash(
		template => 'edit',
		title => 'Editing ',
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
	my $root = path($ENV{BLIPTOWN_USER_HOME}, $username)->to_string;
	my $slug = $c->param('slug');
	$slug =~ s{^/}{};
	my $ext = $c->param('ext');
	my $action = $c->param('action');
	my $filename = "$slug.$ext";
	$filename = path($root, $filename)->to_string;
	my $content = $c->param('content');
	$content =~ s/\r\n/\n/g;
	my $user_rec = $c->user->read_user({ key => 'username', username => $username });
	my $backup = $user_rec->{create_backups} // 0;
	my $res = $c->ipc->send_message({
		command => 'update_file',
		user => $username,
		filename => $filename,
		content => $content,
		create_backup => $backup,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	if ($action eq 'save') {
		return $c->redirect_to($c->url_for('edit_page', catchall => $slug));
	}
	elsif ($action eq 'save-exit') {
		return $c->redirect_to($c->url_for('render_page', catchall => $slug));
	}
}

sub render_raw {
	my $c = shift;
	my $slug = url_unescape $c->param('catchall');
	my $subdir = $c->stash('subdir');
	$slug = "$subdir/" . $slug if $subdir;

	return $c->reply->txt_not_found unless my $file = $c->get_file($slug);
	my $chars = $file->slurp('utf-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
