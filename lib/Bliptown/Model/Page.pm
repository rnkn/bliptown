package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::File qw(path);
use FFI::Platypus;
use YAML::Tiny;
use Mojo::DOM::HTML;
use Mojo::Util qw(dumper);
use Encode;

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
	| MD_FLAG_STRIKETHROUGH;

my $ffi = FFI::Platypus->new(api => 2);
$ffi->lib(path($ENV{'BLIPTOWN_LIB_HOME'}, 'libmd4c.so')->to_string);
$ffi->lib(path($ENV{'BLIPTOWN_LIB_HOME'}, 'libmd4c-html.so')->to_string);
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
	my $args = shift;
	my $html = Mojo::DOM::HTML->new;
	$html->parse($args->{html});
	# say dumper $html->tree;
	return $html->render;
}

sub read_page {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	my $chars = $file->slurp('utf-8');

	my $metadata;
	my $html = '';
	my $html_handler = $ffi->closure(
		sub {
			my ($chunk, $size) = @_;
			my $utf8_text = decode_utf8($chunk);
			$html .= substr($utf8_text, 0, $size);
		}
	);

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
			$metadata = $o->read_string($yaml)->[0];
			$layout = $metadata->{layout} || 'one-column';
		}

		my $octets = encode_utf8($text);
		md_html($octets, length($octets), $html_handler, undef, $md_flags, 0);
		$html = "<section class=\"$layout\">\n" . $html . "</section>\n" if $layout;

		my $partial_re = qr/\{\{ *&gt; *(.*?) *\}\}/;
		while ($html =~ /$partial_re/) {
			my $slug = $1;
			my $root = $args->{root};
			my $recur = $args->{recur} // 0;
			$recur++;
			my $file_str = $slug;
			$file_str =~ s/\.md$//; $file_str = "$file_str.md";

			if ($file_str =~ /^\//) {
				# Absolute path
				$file = path($root, $file_str)->to_abs;
			} else {
				# Relative path
				$file = path($file->dirname, $file_str)->to_abs;
			}

			my @incl_glob_list = glob $file;

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
							recur => $recur,
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
			$html =~ s/\{\{.*?\}\}/$frag/;
		}
		return {
			metadata => $metadata,
			html => $html,
		}
	}
}

return 1;
