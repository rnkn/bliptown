package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(slugify url_unescape);
use Mojo::Home;
use YAML::Tiny;
use Text::Markdown;

sub render_special {
	my ($user, $special) = @_;
	my $home = Mojo::Home->new;
	my $file = $home->child('src', $user, '.' . $special . '.md');
	my $chars = $file->slurp('utf-8');
	my $markdown = $chars;
	$markdown =~ s/\[\[(.*?)\]\]/my $s = slugify($1); "[$1]($s)"/ge;

	my $md = Text::Markdown->new;
	my $html = $md->markdown($markdown);
	return $html;
}

sub render_page {
	my $c = shift;
	my @hostname = split('.', $c->req->url->to_abs->host);
	my $user = @hostname >= 3 ? $hostname[-3] : 'mayor';
	my $path = $c->req->url->to_abs->path;

	$path = url_unescape($path);
	{
		my @path_elts = split('/', $path);
		my @slugs = map { slugify($_) } @path_elts;
		$path = join('/', @slugs);
	}

	$path = 'index' if length($path) == 0;
	my $home = Mojo::Home->new;
	my $file = $home->child('src', $user, $path . '.md');
	# my @file_stats = stat $file;

	return $c->reply->not_found unless -e $file && !-x $file;

	my $chars = $file->slurp('utf-8');
	my ($yaml, $markdown);
	if ($chars =~ /^(---.*?---)\s*(.*)$/s) {
		$yaml = $1;
		$markdown = $2;
	} else {
		$markdown = $chars;
	}

	$markdown =~ s/\[\[(.*?)\]\]/my $s = slugify($1); "[$1]($s)"/ge;
	
	my ($metadata, $title);
	my $layout = 'one-column';
	if ($yaml) {
		$metadata = YAML::Tiny->read_string($yaml);
		$title = 'Bliptown::' . $metadata->[0]->{'title'};
		$layout = $metadata->[0]->{'layout'};
	}

	my $md = Text::Markdown->new;
	my $html = $md->markdown($markdown);

	my $header = render_special($user, 'header');
	my $sidebar = render_special($user, 'sidebar');
	my $footer = render_special($user, 'footer');

	$c->stash(
		template => 'default',
		title => $title,
		layout => $layout,
		header => $header,
		sidebar => $sidebar,
		footer => $footer,
		content => $html,
	);
	return $c->render;
}

return 1;
