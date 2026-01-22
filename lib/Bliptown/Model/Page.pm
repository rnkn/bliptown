package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::File qw(path);
use FFI::Platypus;
use YAML::Tiny;
use POSIX qw(strftime);
use Mojo::DOM::HTML;
use Mojo::Util qw(encode decode);

has 'user';
has 'req_user';

use constant {
	MD_FLAG_COLLAPSEWHITESPACE			=> 1 << 0,
	MD_FLAG_PERMISSIVEATXHEADERS		=> 1 << 1,
	MD_FLAG_PERMISSIVEURLAUTOLINKS		=> 1 << 2,
	MD_FLAG_PERMISSIVEEMAILAUTOLINKS	=> 1 << 3,
	MD_FLAG_NOINDENTEDCODEBLOCKS		=> 1 << 4,
	MD_FLAG_NOHTMLBLOCKS				=> 1 << 5,
	MD_FLAG_NOHTMLSPANS					=> 1 << 6,
	MD_FLAG_TABLES						=> 1 << 8,
	MD_FLAG_STRIKETHROUGH				=> 1 << 9,
	MD_FLAG_PERMISSIVEWWWAUTOLINKS		=> 1 << 10,
	MD_FLAG_TASKLISTS					=> 1 << 11,
	MD_FLAG_LATEXMATHSPANS				=> 1 << 12,
	MD_FLAG_WIKILINKS					=> 1 << 13,
	MD_FLAG_UNDERLINE					=> 1 << 14,
	MD_FLAG_HARD_SOFT_BREAKS			=> 1 << 15,
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
	my ($self, $s) = @_;
	$s =~ s/(?<!\S)'/&lsquo;/g;
	$s =~ s/'/&rsquo;/g;
	$s =~ s/(?<!\S)"/&ldquo;/g;
	$s =~ s/"/&rdquo;/g;
	$s =~ s/---/&mdash;/g;
	$s =~ s/--/&ndash;/g;
	return $s;
}

sub walk_dom {
	my ($self, $node) = @_;

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
		my $converted = $self->convert_typography($content);
		$node->replace($converted);
		return;
	}

	foreach my $child (@{$node->child_nodes}) {
		$self->walk_dom($child);
	}
}

sub error_not_found {
	my ($self, $slug) = @_;
	my $html = <<"EOF";
<span class="error">Error 404: "<a href="$slug">$slug</a>" not found</span>
EOF
	return {
		metadata => {
			title => 'Error 404: File Not Found',
			status => 404,
		},
		html => $html
	}
}

sub error_max_recursion {
	my ($self) = @_;
	my $html = <<'EOF';
<span class="error">Error 508: exceeded maximum level of recursion</span>
EOF
	return {
		metadata => {
			title => 'Error 508: Recursion',
			status => 508,
		},
		html => $html
	};
}

sub collect_blog_posts {
	my ($self, @page_list) = @_;
	@page_list = grep { defined $_->{metadata}->{date} } @page_list;
	@page_list = sort { $b->{metadata}->{date} cmp $a->{metadata}->{date} } @page_list;
	foreach my $page (@page_list) {
		my $html = <<"EOF";

<div class="blog-post">
	$page->{html}
</div>

EOF
		$page->{html} = $html;
	}
	return @page_list;
}

sub process_prettydate {
	my ($self, $date) = @_;
	my $req_user = $self->req_user;
	my ($year, $month, $day) = $date =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})/;
	$year = $year - 1900;
	$month--;
	my %date_formats = (
		0 => '%e %B %Y',
		1 => '%B %e, %Y',
		2 => '%B %Y',
		3 => '%Y',
	);
	my $user = $self->user->read_user(
		{ key => 'username', username => $req_user }
	);
	my $format = $date_formats{$user->{date_format} // 0};
	return strftime($format, 0, 0, 0, $day, $month, $year) // '';
}

sub process_variables {
	my ($self, $html, $args) = @_;
	my $metadata = $args->{metadata};
	my $variable_re = qr/\{\{ *([^>\xA0]+?) *\}\}/;

	while ($html =~ $variable_re) {
		my $key = $1;
		my $val;
		my $date = $metadata->{date};

		if ($date && $key eq 'prettydate') {
			$val = $self->process_prettydate($date);
		} else {
			$val = $metadata->{$key} // '';
		}
		$html =~ s/$variable_re/$val/;
	}
	return $html;
}

sub process_partials {
	my ($self, $html, $args) = @_;
	my $partial_re = qr/(?:<p>)?\{\{ *(?:>|&gt;) *(.*?) *\}\}(?:<\/p>)?/;

	while ($html =~ $partial_re) {
		my $slug = $1;
		my @file_list = $self->glob_path($slug, $args);
		my @page_list;
		foreach my $filename (@file_list) {
			my $page;

			if (!-f $filename) {
				$page = $self->error_not_found($slug);
			} elsif ($args->{recur} >= 64) {
				$page = $self->error_max_recursion;
			} else {
				my %metadata = %{$args->{metadata} // {}};
				$page = $self->read_page(
					{
						root => $args->{root},
						filename => $filename,
						recur => $args->{recur} + 1,
						metadata => \%metadata,
					}
				);
			}

			push @page_list, $page;
		}
		@page_list = $self->collect_blog_posts(@page_list) if scalar @page_list > 1;

		my $frag = join("\n", map { $_->{html} } @page_list);
		$html =~ s/$partial_re/$frag/;
	}
	return $html;
}

sub glob_path {
	my ($self, $slug, $args) = @_;
	my $path = $slug;
	$path =~ s/(\.md)?$/.md/;

	if ($path =~ /^\//) {
		$path = path($args->{root}, $path)->to_abs;
	} else {
		my $file = Mojo::File->new($args->{filename});
		$path = path($file->dirname, $path)->to_abs;
	}

	my @file_list = glob $path;
	@file_list = grep { $_ ne $args->{filename} } @file_list;
	return @file_list;
}

sub split_frontmatter {
	my ($self, $chars) = @_;

	if ($chars =~ /^(---\n.*?---\n)\s*(.*)$/s) {
		return ($1, $2);
	}

	return (undef, $chars);
}

sub parse_yaml {
	my ($self, $yaml) = @_;

	my $yaml_obj = YAML::Tiny->new;
	my $metadata = eval { $yaml_obj->read_string($yaml)->[0] };
	return $metadata;
}

sub markdown_to_html {
	my ($self, $text) = @_;
	my $html = '';

	my $html_handler = $ffi->closure(
		sub {
			my ($chunk, $size) = @_;
			my $bytes = substr($chunk, 0, $size);
			$html .= decode('utf-8', $bytes);
		}
	);

	my $octets = encode('utf-8', $text);
	md_html($octets, length($octets), $html_handler, undef, $md_flags, 0);
	return $html;
}

sub render_plaintext {
	my ($self, $chars, $ext) = @_;

	if ($ext eq 'html') {
		$chars =~ s/&/&amp;/g;
		$chars =~ s/</&lt;/g;
		$chars =~ s/>/&gt;/g;
	}

	my $html = <<"EOF";

<section class="one-column">
	<pre>$chars</pre>
</section>

EOF
	return $html;
}

sub render_markdown {
	my ($self, $text, $args) = @_;

	$text = $self->process_variables($text, $args);
	my $html = $self->markdown_to_html($text);

	if (my $layout = $args->{metadata}->{layout}) {
		$html = <<"EOF";

<section class="$layout">
	$html
</section>

EOF
	}
	return $html;
}

sub read_page {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{filename});
	my $chars = $file->slurp('utf-8');

	$args->{metadata} //= {};
	$args->{recur} //= 0;

	my $html;

	if ($file =~ /\.(txt|html|css|js)$/) {
		$html = $self->render_plaintext($chars, $1);
	} elsif ($file =~ /\.md$/) {
		my ($yaml, $text) = $self->split_frontmatter($chars);

		my $parent_metadata = $args->{metadata};
		delete $parent_metadata->{layout};
		my $child_metadata = $self->parse_yaml($yaml) if $yaml;
		%{$args->{metadata}} = (%$parent_metadata, %$child_metadata) if $child_metadata;

		$html = $self->render_markdown($text, $args);
		$html = $self->process_partials($html, $args);
	}

	unless ($args->{recur}) {
		my $dom = Mojo::DOM->new($html);
		$self->walk_dom($dom);
		$html = $dom->to_string;
	}

	return {
		metadata => $args->{metadata},
		html => $html,
	}
}

return 1;
