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
	my $user = $c->session('username');
	$c->stash( home => $c->get_home );
	my $user_cur = $user && $user eq $c->get_req_user;
	my $slug = $c->param('catchall');
	if (-d $root) {
		my @skel = qw(index.md _title.txt _header.md _sidebar.md _footer.md);
		foreach (@skel) {
			my $f = path($root, $_);
			$f->touch if !-f $f;
		}
	} else {
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

	my $file = $c->get_file($slug);
	if (!$file) {
		if ($user_cur) {
			return $c->redirect_to('new_page');
		} else {
			return $c->reply->not_found;
		}
	}

	my $url = $c->req->url->to_string;
	if ($file =~ /index\.md$/ && $url !~ /\/$/) {
		return $c->redirect_to($url . '/');
	}

	my $page = $c->page->read_page(
		{
			root => $root,
			file => $file
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

	my $page_title = $page->{metadata}{title};
	$title = "$title – $page_title" if $page_title;

	my $date = $page->{metadata}{date};

	my $file_head = path($root, "_head.html");
	my $head = $file_head->slurp('utf-8') if -f $file_head;

	my $show_join = 1
		if $ENV{'BLIPTOWN_JOIN_ENABLED'} == 1
		&& $c->get_req_user eq 'mayor';

	$c->stash(
		template => 'page',
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
	$slug =~ s/\/$//;
	$ext = $1 if $slug =~ /\.(.+)$/;
	$slug = $1 if $slug =~ /(.+)(\..+)$/;
	if ($ext) {
		return $c->reply->not_found unless grep { $ext eq $_} @allowed_exts;
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
	my $root = path($c->get_user_home, $c->get_req_user);
	my $slug = $c->param('catchall');
	$slug =~ s/\/$//;
	my $redirect = $c->param('back_to');
	my $file = $c->get_file($slug) ||
		return $c->redirect_to('new_page', catchall => $slug);
	my $ext = $c->param('ext') || $file->extname || 'md';
	return $c->reply->not_found unless grep { $ext eq $_} @allowed_exts;
	my $rel_file = $file->to_rel($root); $rel_file =~ s/\.[^.]+?$//;
	my $content;
	my @includes;
	if (-f $file) {
		$content = $c->file->read_file({ file => $file })->{chars};
		while ($content =~ /\{\{\s*(.*?)\s*\}\}/g) {
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
	my $user = $c->session('username');
	my $root = path($c->get_user_home, $c->get_req_user)->to_string;
	my $slug = $c->param('slug');
	my $ext = $c->param('ext');
	my $action = $c->param('action');
	my $filename = "$slug.$ext";
	my $file = path($root, $filename)->to_string;
	my $content = $c->param('content');
	$content =~ s/\r\n/\n/g;
	$c->file->update_file(
		{
			command => 'update_file',
			user => $user,
			file => $file,
			content => $content,
		});
	my $redirect;
	if ($action eq 'save-changes') {
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
