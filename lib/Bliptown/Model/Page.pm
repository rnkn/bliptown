package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::Util qw(slugify url_unescape);
use YAML::Tiny;
use Text::Markdown;
use Data::Dumper;

sub read_page {
	my ($self, $args) = @_;
	my $file = $args->{file}->to_abs;
	return unless -r $file;
	my $chars = $file->slurp('utf-8');

	my ($yaml, $text, $metadata, $layout, $html);

	if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
		$yaml = $1;
		$text = $2;
	} else {
		$text = $chars;
	}

	if ($yaml) {
		my $obj = YAML::Tiny->new;
		$metadata = $obj->read_string($yaml);
		$metadata = $metadata->[0];
		$layout = $metadata->{layout} || 'one-column';
	}

	my $obj = Text::Markdown->new;
	$html = $obj->markdown($text);
	$html = "<div class=\"$layout\">\n" . $html . "</div>\n" if $layout;

	while ($html =~ /\{\{s*(.*?)\s*\}\}/) {
		my $path = $1;
		my $home = $args->{home};
		my $user = $args->{user};
		my $transcluded = $args->{transcluded} || [ $file ];
		$path = url_unescape($path);
		{
			my @elts = split('/', $path);
			my @slugs = map { slugify $_ } @elts;
			$path = join('/', @slugs);
		}
		my $file_md = $home->child('src', $user, $path . '.md')->to_abs;
		my $frag = '';
		if (!-e $file_md) {
			$frag = "<span class=\"error\">Error: \"$path\" not found</span>"
		} elsif (grep { $file_md eq $_ } @$transcluded) {
			$frag = '<span class="error">Error: infinite recursion</span>';
		} else {
			push @$transcluded, $file_md;
			say Dumper $transcluded;
			my $page = read_page(
				$self, {
					file => $file_md,
					path => $path,
					home => $home,
					user => $user,
					transcluded => $transcluded,
				});
			$frag = $page->{html};
		}
		$html =~ s/\{\{.*?\}\}/$frag/;
	}
	return {
		metadata => $metadata,
		html => $html,
	};
}

return 1;
