package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::File qw(path);
use Mojo::Util qw(slugify url_unescape);
use YAML::Tiny;
use Text::Markdown;

sub read_page {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	my $chars = $file->slurp('utf-8');

	my $metadata;
	my $html = '';

	if ($file =~ /\.(txt|html|css|js)$/) {
		if ($1 eq 'html') {
			$chars =~ s/&/&amp;/g;
			$chars =~ s/</&lt;/g;
		}
		$html = "<pre>$chars</pre>";
	} elsif ($file =~ /\.md$/) {
		my ($yaml, $text, $layout);

		if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
			$yaml = $1;
			$text = $2;
		} else {
			$text = $chars;
		}

		if ($yaml) {
			my $o = YAML::Tiny->new;
			$metadata = $o->read_string($yaml);
			$metadata = $metadata->[0];
			$layout = $metadata->{layout} || 'one-column';
		}

		my $o = Text::Markdown->new;
		$html = $o->markdown($text);
		$html = "<section class=\"$layout\">\n" . $html . "</section>\n" if $layout;

		while ($html =~ /\{\{\s*(.*?)\s*\}\}/) {
			my $slug = $1;
			my $root = $args->{root};
			my $transcluded = $args->{transcluded} || [ $file ];
			my $file_md;
			if ($slug =~ /^\//) {
				$file_md = path($root, "$slug.md")->to_abs;
			} else {
				$file_md = path($file->dirname, "$slug.md")->to_abs;
			}
			my $frag = '';
			if (!-e $file_md) {
				$frag = "<span class=\"error\">Error: \"<a href=\"$slug\">$slug</a>\" not found</span>"
			} elsif (grep { $file_md eq $_ } @$transcluded) {
				$frag = '<span class="error">Error: infinite recursion</span>';
			} else {
				push @$transcluded, $file_md;
				my $page = read_page(
					$self, {
						root => $root,
						file => $file_md,
						transcluded => $transcluded,
					});
				$frag = $page->{html};
			}
			$html =~ s/\{\{.*?\}\}/$frag/;
		}
	}
	return {
		metadata => $metadata,
		html => $html,
	}
}

return 1;
