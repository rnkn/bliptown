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
		my @skel = qw(index _header _sidebar _footer);
		foreach (@skel) {
			path($root, "$_.md")->touch;
		}
	}
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;

	# my $home = Mojo::URL->new;
	# $c->session('username') . '.' . $c->cookie('domain');
	# $c->log->debug(dumper $home);

	my $raw = path($root, $slug);
	return $c->reply->not_found if $raw->extname && !-f $raw;
	return $c->reply->file($raw) if -f $raw;

	$slug = url_unescape($slug);
	{
		my @elts = split('/', $slug);
		@elts = map { slugify $_ } @elts;
		$slug = join('/', @elts);
	}

	my $file = $c->get_file($slug);
	return $c->redirect_to('new_page') unless -f $file;

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

	my $title = $page->{metadata}{title};
	my $date = $page->{metadata}{date};

	my @special_pages = qw(header sidebar footer);
	my %special_html;
	foreach (@special_pages) {
		my $file_md = path($root, "_$_.md");
		my $page = $c->page->read_page(
			{
				file => $file_md,
				root => $root,
			}
		) if -e $file_md;
		$special_html{$_} = $page->{html};
	}
	my $file_head = path($root, "_head.html");
	my $head = $file_head->slurp('utf-8') if -e $file_head;

	my $show_join = 1 if $ENV{'BLIPTOWN_JOIN_ENABLED'} == 1
		&& $c->get_domain_user eq 'mayor';

	$c->stash(
		template => 'page',
		home => $c->get_home,
		head => $head || '',
		title => $title,
		date => $date,
		header => $special_html{header} || '',
		sidebar => $special_html{sidebar} || '',
		footer => $special_html{footer} || '',
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
	$slug = 'index' if length($slug) == 0;
	$slug =~ s/\.[^.]+?$//;
	my $redirect = $c->param('back_to');
	my $file = $c->get_file($slug) || path($root, "$slug.md");
	my $ext = $file->extname;
	my $content = '';
	my @includes;
	if (-e $file) {
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
		slug => $slug,
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
	my $file = path($root, "$slug.$ext");
	my $chars = $c->param('content');
	$chars =~ s/\r\n/\n/g;
	$c->file->update_file(
		{
			file => $file,
			chars => $chars,
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
