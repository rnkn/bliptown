package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(slugify url_unescape);
use Mojo::File qw(path);

sub yaml_true {
	my $p = shift;
	if ($p && $p =~ /^(true|y(es)?|1)$/) {
		return 1;
	}
}

sub render_page {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->get_domain_user);
	if (-d $root) {
		my @skel = qw(index.md _title.txt _header.md _sidebar.md _footer.md);
		foreach (@skel) {
			path($root, $_)->touch;
		}
	}
	my $slug = $c->param('catchall');

	my $raw = path($root, $slug);
	if ($raw->extname) {
		return $c->reply->file($raw) if -f $raw;
		my $fallback = path($c->app->static->paths->[0], 'fallback', $slug);
		return $c->reply->file($fallback) if -f $fallback;
		return $c->reply->not_found;
	}

    unless ($c->req->url->to_abs =~ /\/$/) {
        return $c->redirect_to($c->req->url->to_abs . '/');
    }

	$slug = url_unescape($slug);
	{
		my @elts = split('/', $slug);
		@elts = map { slugify $_ } @elts;
		$slug = join('/', @elts);
	}

	my $file = $c->get_file($slug);
	if (!-f $file) {
		my $u = $c->session('username');
		if ($u && $u eq $c->get_domain_user) {
			return $c->redirect_to('new_page');
		} else {
			return $c->reply->not_found;
		}
	}

	my $page = $c->page->read_page(
		{
			root => $root,
			file => $file
		}
	);

	# my $private = $page->{metadata}{private};
	
	# return $c->render(
	# 	text => 'Access denied', status => 403
	# ) if yaml_true($private);

	my @skel = qw(_header _sidebar _footer);
	my %skel_html;
	foreach (@skel) {
		my $f = path($root, "$_.md");
		my $page = $c->page->read_page(
			{
				file => $f,
				root => $root,
			}
		);
		$skel_html{$_} = $page->{html};
	}

	my $title_f = path($root, "_title.txt");
	my $title = "Untitled";
	if (-f $title_f) {
		open(my $fh, '<', $title_f);
		$title = <$fh>;
		close($fh);
	}

	my $page_title = $page->{metadata}{title};
	$title = "$title – $page_title" if $page_title;

	my $date = $page->{metadata}{date};

	my $file_head = path($root, "_head.html");
	my $head = $file_head->slurp('utf-8') if -e $file_head;

	my $show_join = 1 if $ENV{'BLIPTOWN_JOIN_ENABLED'} == 1
		&& $c->get_domain_user eq 'mayor';

	$c->stash(
		template => 'page',
		home => $c->get_home,
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
	$slug =~ s/\/$//;
	$c->stash(
		template => 'edit',
		title => 'New',
		slug => $slug,
		redirect => $c->url_for('edit_page', catchall => $slug),
	);
	return $c->render;
}

sub edit_page {
	my $c = shift;
	my $root = path($c->get_src_dir, $c->get_domain_user);
	my $slug = $c->param('catchall');
	my $redirect = $c->param('back_to');
	$slug =~ s/\/$//; $slug =~ s/\.[^.]+?$//;
	my $file = $c->get_file($slug) || path($root, "$slug.md");
	my $rel = $file->to_rel($root); $rel =~ s/\.[^.]+?$//;
	my $ext = $c->param('ext') || $file->extname;
	my $content = '';
	my @includes;
	if (-f $file) {
		$content = $c->file->read_file({ file => $file })->{chars};
		while ($content =~ /\{\{\s*(.*?)\s*\}\}/g) {
			unless (grep { $_ eq $1 } @includes ) {
				push @includes, $1;
			}
		}
	}
	$c->stash(
		template => 'edit',
		title => 'Editing ',
		slug => $rel,
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
	my $root = path($c->get_src_dir, $c->get_domain_user);
	my $slug = $c->param('slug');
	{
		my @elts = split('/', $slug);
		@elts = map { slugify $_ } @elts;
		$slug = join('/', @elts);
	}
	my $ext = $c->param('ext');
	my $action = $c->param('action');
	my $filename = "$slug.$ext";
	my $trigger = 'pubkeys' if $filename eq '_pubkeys.txt';
	my $filepath = path($root, $filename);
	my $chars = $c->param('content');
	$chars =~ s/\r\n/\n/g;
	$c->file->update_file(
		{
			file => $filepath,
			chars => $chars,
			trigger => $trigger,
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
	my $root = path($c->get_src_dir, $c->get_domain_user);
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $file = $c->get_file($slug);
	return $c->reply->not_found unless -f $file;
	my $chars = $file->slurp('utf-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
