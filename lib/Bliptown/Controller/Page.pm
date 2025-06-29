package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(slugify url_unescape);
use Mojo::Home;
use YAML::Tiny;
use Text::Markdown;

sub render_page {
	my $c = shift;
	my @hostname = split('.', $c->req->url->to_abs->host);
	my $user = @hostname >= 3 ? $hostname[-3] : 'mayor';
	my $home = Mojo::Home->new;
	my $path = $c->req->url->to_abs->path;
	$path = url_unescape($path);
	$path =~ s/^\///;
	$path = slugify($path);
	$path = 'index' if length($path) == 0;
	my $file = $home->child('src', $user, $path . '.md');
	my $chars = $file->slurp('utf-8');
	my ($yaml, $markdown);
	if ($chars =~ /^(---.*?---)\s*(.*)$/s) {
		$yaml = $1;
		$markdown = $2;
	} else {
		$markdown = $chars;
	}

	$markdown =~ s/\[\[(.*?)\]\]/my $s = slugify($1); "[$1]($s)"/ge;
	$c->app->log->debug($markdown);
	
	my $metadata = YAML::Tiny->read_string($yaml);
	my $title = 'Bliptown::' . $metadata->[0]->{'title'};
	my $layout = $metadata->[0]->{'layout'};

	my $md = Text::Markdown->new;
	my $html = $md->markdown($markdown);

	$c->stash(
		template => 'default',
		title => $title,
		class => $layout,
		content => $html,
	);
	return $c->render;
}

return 1;
