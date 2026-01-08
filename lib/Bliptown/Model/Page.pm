package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::File qw(path);
use FFI::Platypus;
use YAML::Tiny;
use Mojo::DOM::HTML;
use Mojo::Util qw(encode decode);

use constant {
	MD_FLAG_COLLAPSEWHITESPACE          => 1 << 0,
	MD_FLAG_PERMISSIVEATXHEADERS        => 1 << 1,
	MD_FLAG_PERMISSIVEURLAUTOLINKS      => 1 << 2,
	MD_FLAG_PERMISSIVEEMAILAUTOLINKS    => 1 << 3,
	MD_FLAG_NOINDENTEDCODEBLOCKS        => 1 << 4,
	MD_FLAG_NOHTMLBLOCKS                => 1 << 5,
	MD_FLAG_NOHTMLSPANS                 => 1 << 6,
	MD_FLAG_TABLES                      => 1 << 8,
	MD_FLAG_STRIKETHROUGH               => 1 << 9,
	MD_FLAG_PERMISSIVEWWWAUTOLINKS      => 1 << 10,
	MD_FLAG_TASKLISTS                   => 1 << 11,
	MD_FLAG_LATEXMATHSPANS              => 1 << 12,
	MD_FLAG_WIKILINKS                   => 1 << 13,
	MD_FLAG_UNDERLINE                   => 1 << 14,
	MD_FLAG_HARD_SOFT_BREAKS            => 1 << 15,
};

my $md_flags = MD_FLAG_PERMISSIVEURLAUTOLINKS
	| MD_FLAG_PERMISSIVEEMAILAUTOLINKS
	| MD_FLAG_TABLES
	| MD_FLAG_STRIKETHROUGH
	| MD_FLAG_WIKILINKS;

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib(path($ENV{'BLIPTOWN_MD4C_LIB'})->to_string);
$ffi->lib(path($ENV{'BLIPTOWN_MD4C_HTML_LIB'})->to_string);
$ffi->type('(string, int, opaque)->void' => 'callback');
$ffi->attach(
	md_html => [
		'string',
		'uint',
		'callback',
		'opaque',
		'uint',
		'uint'
	] => 'int'
);

sub convert_typography {
	my $s = shift;
	$s =~ s/(?<!\S)'/&lsquo;/g;
	$s =~ s/'/&rsquo;/g;
	$s =~ s/(?<!\S)"/&ldquo;/g;
	$s =~ s/"/&rdquo;/g;
	$s =~ s/---/&mdash;/g;
	$s =~ s/--/&ndash;/g;
	return $s;
}

sub walk_dom {
	my $node = shift;
	
	my @skip_tags = qw(pre code kbd script);

	return if $node->tag && grep { $node->tag eq $_ } @skip_tags;

	if ($node->tag && $node->tag eq 'x-wikilink') {
		my $href=$node->attr('data-target');
		delete $node->attr->{'data-target'};
		$node->tag('a');
		$node->attr({ href => $href });
		return;
	}

    if ($node->type eq 'text') {
		my $content = $node->content;
        my $converted = convert_typography($content);
        $node->replace($converted);
        return;
    }

	foreach my $child ($node->child_nodes->each) {
		walk_dom($child);
	}
}

sub read_page {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	my $chars = $file->slurp('utf-8');
	my $recur = $args->{recur} // 0;

	my $metadata;
	my $html = '';
	my $html_handler = $ffi->closure(
		sub {
			my ($chunk, $size) = @_;
			my $bytes = substr($chunk, 0, $size);
			$html .= decode('utf-8', $bytes);
		}
	);

	if ($file =~ /\.(txt|html|css|js)$/) {
		if ($1 eq 'html') {
			$chars =~ s/&/&amp;/g;
			$chars =~ s/</&lt;/g;
		}
		$html = "<section class=\"one-column\">\n<pre>$chars</pre></section>\n";
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
			$metadata = eval { $o->read_string($yaml)->[0] };
			$layout = $metadata->{layout} || '';
		}

		my $octets = encode('utf-8', $text);
		md_html($octets, length($octets), $html_handler, undef, $md_flags, 0);
		$html = "<section class=\"$layout\">\n" . $html . "</section>\n" if $layout;

		my $partial_re = qr/(?:<p>)?\{\{ *(?:>|&gt;) *(.*?) *\}\}(?:<\/p>)?/;
		while ($html =~ /$partial_re/) {
			my $slug = $1;
			my $root = $args->{root};
			my $file_str = $slug;
			$file_str =~ s/\.md$//; $file_str = "$file_str.md";
			my $path;

			if ($file_str =~ /^\//) {
				# Absolute path
				$path = path($root, $file_str)->to_abs;
			} else {
				# Relative path
				$path = path($file->dirname, $file_str)->to_abs;
			}

			my @incl_glob_list = glob $path;

			my @page_list;
			foreach my $filename (@incl_glob_list) {
				my $file = Mojo::File->new($filename);
				my $page;

				if (!-f $filename) {
					$page = {
						metadata => {
							title => 'Error: File Not Found',
							status => 404,
						},
						html => "<span class=\"error\">Error: \"<a href=\"$slug\">$slug</a>\" not found</span>",
					}
				} elsif ($recur >= 64) {
					$page = {
						metadata => {
							title => 'Error: Recursion',
							status => 508,
						},
						html => '<span class="error">Error: exceeded maximum level of recursion</span>',
					}
				} else {
					$page = read_page(
						$self, {
							root => $root,
							file => $file,
							recur => $recur + 1,
						}
					);
				}
				push @page_list, $page;
			}
			if (scalar @page_list > 1) {
				@page_list = grep { defined $_->{metadata}->{date} } @page_list;
				@page_list = sort { $b->{metadata}->{date} cmp $a->{metadata}->{date} } @page_list;
				map {
					$_->{html} = "<div class=\"blog-post\">$_->{html}</div>"; $_
				} @page_list;
			}
			my $frag = join("\n", map { $_->{html} } @page_list);
			$html =~ s/$partial_re/$frag/;
		}
	}

	unless ($recur) {
		my $dom = Mojo::DOM->new($html);
		walk_dom($dom);
		$html = $dom->to_string;
	}

	return {
		metadata => $metadata,
		html => $html,
	}
}

return 1;
