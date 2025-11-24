package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(url_unescape);
use Mojo::File qw(path);

sub yaml_true {
	my $p = shift;
	if ($p && $p =~ /^(true|y(es)?|1)$/) {
		return 1;
	}
}

my @allowed_exts = qw(html css js txt md);

sub render_page {
	my $c = shift;
	my $root = path($c->get_user_home, $c->get_req_user);
	my $username = $c->session('username');
	$c->stash( home => $c->get_home );
	my $user_cur = $username && $username eq $c->get_req_user;
	my $slug = $c->param('catchall');
	unless (-d $root && $root gt $c->get_user_home) {
		return $c->reply->not_found;
	}

	my $raw = path($root, $slug);
	if ($raw->extname) {
		return $c->reply->file($raw) if -f $raw;
		my $fallback = path($c->app->static->paths->[0], 'defaults', $slug);
		return $c->reply->file($fallback) if -f $fallback;
		return $c->reply->not_found;
	}

	$slug = url_unescape($slug);

	my $file;
	if (!$slug || $slug =~ /\/$/) {
		unless ($file = $c->get_file("$slug/index")) {
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
			return $c->redirect_to('new_page');
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

	my @skel = qw(_header _sidebar _footer);
	my %skel_html;
	foreach (@skel) {
		my $file = path($root, "$_.md");
		my $page = $c->page->read_page(
			{
				file => $file,
				root => $root,
			}
		);
		$skel_html{$_} = $page->{html};
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
		if $ENV{'BLIPTOWN_JOIN_ENABLED'} == 1
		&& $c->get_req_user eq 'mayor';

	$c->stash(
		template => 'page',
		stage => 'foh',
		head => $head || '',
		title => $title,
		header => $skel_html{_header} || '',
		sidebar => $skel_html{_sidebar} || '',
		footer => $skel_html{_footer} || '',
		content => $page->{html},
		editable => 1,
		redirect => $c->url_for('render_page'),
		show_join => $show_join,
	);
	return $c->render;
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
				$c->redirect_to('edit_page', catchall => $slug);
			}
		};
	} else {
		unless ($c->get_file($slug)) {
			if ($c->get_file("$slug/index")) {
				$c->redirect_to('edit_page', catchall => "$slug/");
			}
		}
	}
	$c->stash(
		template => 'edit',
		title => 'New',
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
	my $partial_re = qr/\{\{ *> *(.*?) *\}\}/;
	my $root = path($c->get_user_home, $c->get_req_user);
	my $file;
	if (!$slug || $slug =~ /\/$/) {
		unless ($file = $c->get_file("$slug/index")) {
			$slug =~ s/\/$//;
			if ($file = $c->get_file($slug)) {
				$c->redirect_to('edit_page', catchall => $slug);
			}
		};
	} else {
		unless ($file = $c->get_file($slug)) {
			if ($file = $c->get_file("$slug/index")) {
				$c->redirect_to('edit_page', catchall => "$slug/");
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
		while ($content =~ /$partial_re/g) {
			unless (grep { $1 eq $_ } @includes ) {
				my $include = $1; $include =~ s/\.[^.]+?$//;
				push @includes, $include;
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
	my $root = path($c->get_user_home, $c->get_req_user)->to_string;
	my $slug = $c->param('slug');
	my $ext = $c->param('ext');
	my $action = $c->param('action');
	my $filename = "$slug.$ext";
	my $file = path($root, $filename)->to_string;
	my $content = $c->param('content');
	$content =~ s/\r\n/\n/g;
	$c->ipc->send_message(
		{
			command => 'update_file',
			username => $username,
			filename => $file,
			content => $content,
		});
	my $redirect;
	if ($action eq 'save') {
		return $c->redirect_to($c->url_for('edit_page', catchall => $slug));
	} elsif ($action eq 'save-exit') {
		return $c->redirect_to($c->url_for('render_page', catchall => $slug));
	}
}

sub render_raw {
	my $c = shift;
	my $slug = $c->param('catchall');
	my $file = $c->get_file($slug);
	return $c->reply->not_found unless -f $file;
	my $chars = $file->slurp('utf-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
