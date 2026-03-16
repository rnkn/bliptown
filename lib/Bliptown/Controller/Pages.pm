package Bliptown::Controller::Pages;
use Mojo::Base 'Mojolicious::Controller';
use YAML::Tiny;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape sha1_sum);

sub process_redirects {
	my ($file, $slug) = @_;
	$slug =~ s{^/?}{/};
	$slug =~ s{/?$}{};
	my $chars = $file->slurp('utf-8');
	my $yaml_obj = YAML::Tiny->new;
	my $redirects = eval { $yaml_obj->read_string($chars)->[0] };
	my $url = $redirects->{$slug};
	return $url if $url;
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

sub render_page {
	my $c = shift;
	my $user_home = $c->config->{user_home};
	my $req_user = $c->get_req_user;
	return $c->reply->not_found unless $req_user;
	my $root = path($user_home, $req_user);
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
			my @cached_exts = qw(eot ttf woff woff2 jpg jpeg png webp gif mp3 mp4 mpeg webm);
			my $cached = grep { $ext eq $_ } @cached_exts;
			if ($c->app->mode eq 'production' && $cached) {
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

	my $page = $c->page->read_page(
		{
			root => $root->to_abs->to_string,
			filename => $file->to_abs->to_string,
		}
	);

	my @skel = qw(header sidebar footer);
	my %skel_html;
	my $show_sidebar = 0;
	foreach my $f (@skel) {
		my $file = path($root, "_$f.md");
		if (-f $file) {
			$show_sidebar = 1 if $f eq 'sidebar';
			my $page = $c->page->read_page(
				{
					filename => $file->to_abs->to_string,
					root => $root->to_abs->to_string,
				}
			);
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

	my $date = $page->{metadata}->{date};

	my $file_head = path($root, "_head.html");
	my $head = $file_head->slurp('utf-8') if -f $file_head;
	my $file_scripts = path($root, "_scripts.js");
	my $scripts = $file_scripts->slurp('utf-8') if -f $file_scripts;

	$c->stash(
		template => 'page',
		title => $title,
		head => $head || '',
		scripts => $scripts || '',
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

sub new_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $ext = '';
	if ($slug =~ /(.+)\.([^.]+)$/) {
		 $slug = $1;
		 $ext = $2;
	};
	if ($ext) {
		return $c->reply->not_found unless grep { $ext eq $_} @{$c->config->{allowed_exts}};
	}
	my $file;
	if (!$slug || $slug =~ m{/$}) {
		unless ($c->get_file("$slug/index")) {
			$slug =~ s{/$}{};
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
	my $username = $c->session('username');
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to');
	my $partial_re = qr/^\Q{{\E *> *(.*?) *\Q}}\E$/;
	my $root = path($c->config->{user_home}, $username);
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
	return $c->reply->not_found unless grep { $ext eq $_} @{$c->config->{allowed_exts}};
	my $rel_file = $file->to_rel($root); $rel_file =~ s/\.[^.]+?$//;
	my $content;
	my @includes;
	if (-f $file) {
		$content = $c->file->read_file({ file => $file })->{chars};
		my @lines = split /\n/, $content;
		foreach my $line (@lines) {
			if ($line =~ $partial_re) {
				my $include = $1;
				$include =~ s{\.[^.]+?$}{};
				my $abs_url = Mojo::URL->new('/' . $slug);
				$include = Mojo::URL->new($include)->to_abs($abs_url)->to_string;
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
	my $root = path($c->config->{user_home}, $username)->to_string;
	my $slug = $c->param('slug');
	$slug =~ s{^/}{};
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
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	if ($action eq 'save') {
		return $c->redirect_to($c->url_for('edit_page', catchall => $slug));
	} elsif ($action eq 'save-exit') {
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
