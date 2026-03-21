package Bliptown::Model::Mustache;
use Mojo::Base -base;
use Mojo::File;

has 'user';
has 'metadata';
has 'util';

sub process {
	my ($self, $text, $args) = @_;
	$text = $self->process_sections($text, $args);
	$text = $self->process_partials($text, $args);
	$text = $self->apply_layout($text, $args) if $args->{metadata}->{layout};
	$text = $self->process_variables($text, $args);
	return $text;
}

sub apply_layout {
	my ($self, $text, $args) = @_;
	my $layout = $args->{metadata}->{layout};
	return <<"EOF";
<section class="$layout">

$text

</section>
EOF
}

sub process_variables {
	my ($self, $text, $args) = @_;
	my $metadata = $args->{metadata};
	my $variable_re = qr/\{\{\s*([[:alnum:]\s_-]+?)\s*\}\}/;

	while ($text =~ $variable_re) {
		my $key = $1;
		my $val;
		my $date = $metadata->{date};

		if ($date && $key eq 'prettydate') {
			$val = $self->util->process_prettydate($date);
		} else {
			$val = $metadata->{$key} // '';
		}
		$text =~ s/$variable_re/$val/;
	}
	return $text;
}

sub process_sections {
	my ($self, $text, $args) = @_;
	my $section_re = qr/\{\{\s*#\s*([^\n]+?)\s*\}\}\n(.*?)\n?\{\{\s*\/\s*\}\}/s;

	while ($text =~ $section_re) {
		my ($glob, $template) = ($1, $2);
		my @file_list = $self->util->glob_path($glob, $args);

		my @items;
		foreach my $filename (@file_list) {
			next unless -f $filename;
			my $chars = Mojo::File->new($filename)->slurp('utf-8');
			my ($yaml, $text) = $self->util->split_frontmatter($chars);
			my $metadata = $yaml ? $self->metadata->read_metadata($yaml) : {};
			next unless $metadata && $metadata->{date};

			my %parent_metadata = %{$args->{metadata} // {}};
			my %child_metadata = (%parent_metadata, %$metadata);
			$child_metadata{url} = $self->util->file_to_slug($filename, $args);

			push @items, \%child_metadata;
		}

		@items = sort { $b->{date} cmp $a->{date} } @items;

		my $result = join "\n", map {
			$self->process_variables($template, { metadata => $_ })
		} @items;

		$text =~ s/$section_re/$result/s;
	}
	return $text;
}

sub process_partials {
	my ($self, $text, $args) = @_;
	my $partial_re = qr/\{\{\s*>\s*(.+?)\s*\}\}/;

	while ($text =~ $partial_re) {
		my $slug = $1;
		my @file_list = $self->util->glob_path($slug, $args);

		my $partial = '';
		my @partial_list;
		foreach my $filename (@file_list) {
			if (!-f $filename) {
				$partial = $self->error_not_found($slug);
			} elsif (($args->{recur} // 0) >= 64) {
				$partial = $self->error_max_recursion();
			} else {
				$partial = $self->read_partial($filename, $args);
			}
			push @partial_list, $partial if defined $partial;
		}

		if (scalar @partial_list > 1) {
			@partial_list = @{$self->collect_partials(\@partial_list)};
			$partial = join "\n", @partial_list;
		} elsif (@partial_list) {
			$partial = $partial_list[0]->{html} // '';
		}
		$text =~ s/$partial_re/$partial/;
	}
	return $text;
}

sub collect_partials {
	my ($self, $partial_list) = @_;
	@$partial_list = grep { defined $_->{metadata}->{date} } @$partial_list;
	@$partial_list = sort { $b->{metadata}->{date} cmp $a->{metadata}->{date} } @$partial_list;
	@$partial_list = map { <<"EOF"
<div class="blog-post">

$_->{html}

</div>
EOF
	} @$partial_list;
	return $partial_list;
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

sub read_partial {
	my ($self, $filename, $args) = @_;
	return unless $filename =~ /\.md$/;

	my $chars = Mojo::File->new($filename)->slurp('utf-8');
	my ($yaml, $text) = $self->util->split_frontmatter($chars);

	my %metadata = %{$args->{metadata} // {}};
	delete $metadata{layout};
	my $child_metadata = $yaml ? $self->metadata->read_metadata($yaml) : {};
	%metadata = (%metadata, %$child_metadata) if $child_metadata;

	my $child_args = {
		root     => $args->{root},
		filename => $filename,
		recur    => ($args->{recur} // 0) + 1,
		metadata => \%metadata,
	};

	return {
		html     => $self->process($text, $child_args),
		metadata => \%metadata,
	};
}

return 1;
