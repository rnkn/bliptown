package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(slugify url_unescape);

my @special_pages = ('header', 'sidebar', 'footer');

sub render_frag {
	my $page = shift;
	my $layout = $page->{metadata}{layout} // 'one-column';
	return "<div class=\"$layout\">\n" . $page->{html} . "</div>\n";
}

sub yaml_true {
	my $p = shift;
	if ($p && $p =~ /^(true|y(es)?|1)$/) {
		return 1;
	}
}

sub render_page {
	my $c = shift;
	my $home = $c->get_home;
	my $path = $c->req->url->to_abs->path;
	my $user = $c->get_user;

	$path = url_unescape($path);
	{
		my @elts = split('/', $path);
		my @slugs = map { slugify $_ } @elts;
		$path = join('/', @slugs);
	}
	$path = 'index' if length($path) == 0;

	my $file_html = $home->child('src', $user, $path . '.html');
	my $file_md = $home->child('src', $user, $path . '.md');

	return $c->reply->file($file_html) if -r $file_html;
	return $c->reply->not_found unless -r $file_md;

	my $page = $c->page->read_page(
		{
			file => $file_md,
			user => $user,
			path => $path,
			home => $home,
		});

	my $private = $page->{metadata}{private};
	
	return $c->render(
		text => 'Access denied', status => 403
	) if yaml_true($private);

	my $title = $page->{metadata}{title} || 'Untitled';
	my $date = $page->{metadata}{date} || '';

	my %special_html;
	foreach (@special_pages) {
		my $file_md = $home->child('src', $user, '.' . $_ . '.md');
		my $page = $c->page->read_page({ file => $file_md });
		$special_html{$_} = $page->{html};
	}
	$special_html{head_add} = $home->child('src', $user, '.head.html')->slurp('utf-8');

	$c->stash(
		template => 'page',
		head_add => $special_html{head_add},
		title => $title,
		date => $date,
		header => $special_html{header},
		sidebar => $special_html{sidebar},
		footer => $special_html{footer},
		content => $page->{html},
	);
	return $c->render;
}

return 1;
