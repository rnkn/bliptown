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

sub get_file {
	my ($dir, $slug) = @_;
	my @filetypes = qw(html css js txt md);
	my $file;
	foreach (@filetypes) {
		my $f = path($dir, "$slug.$_")->to_abs;
		return $f if -e $f;
	}
}

sub render_page {
	my $c = shift;
	my $dir = $c->app->home->child($c->get_src_dir, $c->get_user); # FIXME
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;

	my $raw = path($dir, $slug)->to_string;
	return $c->reply->file($raw) if -e $raw;

	$slug = url_unescape($slug);
	# {
	# 	my @elts = split('/', $slug);
	# 	@elts = map { slugify $_ } @elts;
	# 	$slug = join('/', @elts);
	# }

	my $file = get_file($dir, $slug);

	return $c->reply->not_found unless $file;
	return $c->reply->file($file) if $file =~ /\.html$/;

	my $page = $c->page->read_page({ file => $file });

	# my $private = $page->{metadata}{private};
	
	# return $c->render(
	# 	text => 'Access denied', status => 403
	# ) if yaml_true($private);

	my $title = $page->{metadata}{title} || 'Untitled';
	my $date = $page->{metadata}{date} || '';

	my @special_pages = qw(header sidebar footer);
	my %special_html;
	my $cur_dir = $file->dirname;
	foreach (@special_pages) {
		my $file_md = path($cur_dir, ".$_.md");
		my $page = $c->page->read_page({ file => $file_md });
		$special_html{$_} = $page->{html};
	}
	my $head = path($dir, ".head.html")->slurp('utf-8');

	$c->stash(
		template => 'page',
		head => $head,
		title => $title,
		date => $date,
		header => $special_html{header},
		sidebar => $special_html{sidebar},
		footer => $special_html{footer},
		content => $page->{html},
		editable => 1,
		redirect => $c->url_for('render_page'),
	);
	return $c->render;
}

sub list_pages {
	my $c = shift;
	my $dir = $c->app->home->child($c->get_src_dir, $c->get_user); # FIXME
	my $files = $dir->list({ hidden => 1 })->to_array;
	my $redirect = $c->url_for('list_pages');
	my %pages;
	foreach (@$files) {
		my ($slug) = path($_)->basename(qw(.md .txt .js .css .html));
		$pages{$slug} = $c->page->read_page({ file => $_});
	}
	$c->stash(
		head => '',
		template => 'all-pages',
		title => 'All Pages',
		editable => 0,
		redirect => $redirect,
		pages => \%pages,
	);
	return $c->render;
}

sub edit_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $redirect = $c->param('back_to');
	my $dir = $c->app->home->child($c->get_src_dir, $c->get_user); # FIXME
	my $file = get_file($dir, $slug);
	my $content = $c->source->read_source({ file => $file })->{chars};
	my @included = ($content =~ /\{\{\s*(.*?)\s*\}\}/g);
	$c->stash(
		head => '',
		template => 'edit',
		title => 'Editing ',
		filename => $file->basename,
		slug => $slug,
		editable => 0,
		redirect => $redirect,
		content => $content,
		included => \@included,
	);
	return $c->render;
	
}

sub save_page {
	my $c = shift;
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $action = $c->param('action');
	my $redirect = $c->param('back_to');
	$redirect = $c->url_for('edit_page')->query(back_to => $redirect) if $action eq 'save-changes';
	my $dir = $c->app->home->child($c->get_src_dir, $c->get_user); # FIXME
	my $file = get_file($dir, $slug);
	my $chars = $c->param('content');
	$chars =~ s/\r\n/\n/g;
	$c->source->update_source(
		{
			file => $file,
			chars => $chars,
		});
	return $c->redirect_to($redirect);
}

sub render_raw {
	my $c = shift;
	my $slug = $c->param('catchall');
	$slug = 'index' if length($slug) == 0;
	my $dir = $c->app->home->child($c->get_src_dir, $c->get_user); # FIXME
	my $file = get_file($dir, $slug);
	my $chars = $file->slurp('utf-8');
	return $c->render(text => $chars, format => 'txt');
}

return 1;
