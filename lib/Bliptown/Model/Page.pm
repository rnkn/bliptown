package Bliptown::Model::Page;
use Mojo::Base -base;
use Mojo::File qw(path);
use FFI::Platypus;
use Mojo::DOM;
use Mojo::Util qw(encode decode);

has 'req_user';
has 'user';
has 'metadata';
has 'mustache';
has 'util';

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
		my $href = $node->attr('data-target');
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

sub read_page {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{filename});
	my $chars = $file->slurp('utf-8');

	$args->{metadata} //= {};
	$args->{recur} //= 0;

	my $html = '';

	if ($file =~ /\.(txt|html|css|js)$/) {
		$html = $self->render_plaintext($chars, $1);
	}
	elsif ($file =~ /\.md$/) {
		my ($yaml, $text) = $self->util->split_frontmatter($chars);
		my $parent_metadata = $args->{metadata};
		delete $parent_metadata->{layout};
		my $child_metadata = $self->metadata->read_metadata($yaml) if $yaml;
		%{$args->{metadata}} = (%$parent_metadata, %$child_metadata) if $child_metadata;

		$text = $self->mustache->process($text, $args);
		$html = $self->markdown_to_html($text);
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
