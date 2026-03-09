package Bliptown::Model::Mustache;
use Mojo::Base -base;
use Mojo::File;

has 'page';

sub process {
	my ($self, $text, $args) = @_;
	$text = $self->process_variables($text, $args);
	$text = $self->process_sections($text, $args);
	$text = $self->process_partials($text, $args);
	return $text;
}

sub process_variables {
	my ($self, $text, $args) = @_;
	my $metadata = $args->{metadata};
	my $variable_re = qr/\{\{ *([^#>\/\s\xA0][^>\xA0]*?) *\}\}/;

	while ($text =~ $variable_re) {
		my $key = $1;
		my $val;
		my $date = $metadata->{date};

		if ($date && $key eq 'prettydate') {
			$val = $self->page->process_prettydate($date);
		} else {
			$val = $metadata->{$key} // '';
		}
		$text =~ s/$variable_re/$val/;
	}
	return $text;
}

sub process_sections {
	my ($self, $text, $args) = @_;
	my $section_re = qr/\{\{ *# *(.*?) *\}\}\n(.*?)\n?\{\{ *\/ *\}\}/s;

	while ($text =~ $section_re) {
		my ($glob, $template) = ($1, $2);
		my @file_list = $self->page->glob_path($glob, $args);

		my @items;
		foreach my $filename (@file_list) {
			next unless -f $filename;
			my $chars = Mojo::File->new($filename)->slurp('utf-8');
			my ($yaml, $file_text) = $self->page->split_frontmatter($chars);
			my $file_metadata = $yaml ? $self->page->parse_yaml($yaml) : {};
			next unless $file_metadata && defined $file_metadata->{date};

			my %item_metadata = %{$args->{metadata} // {}};
			delete $item_metadata{layout};
			%item_metadata = (%item_metadata, %$file_metadata);
			delete $item_metadata{layout};
			$item_metadata{slug} = $self->page->file_to_slug($filename, $args);

			push @items, \%item_metadata;
		}

		@items = sort { $b->{date} cmp $a->{date} } @items;

		my $result = join("\n", map {
			my $item_text = $template;
			$item_text = $self->process_variables($item_text, { metadata => $_ });
			$item_text;
		} @items);

		$text =~ s/$section_re/$result/s;
	}
	return $text;
}

sub process_partials {
	my ($self, $text, $args) = @_;
	my $partial_re = qr/\{\{ *> *(.*?) *\}\}/;

	while ($text =~ $partial_re) {
		my $slug = $1;
		my @file_list = $self->page->glob_path($slug, $args);

		my $frag = '';
		foreach my $filename (@file_list) {
			if (!-f $filename) {
				$frag .= $self->page->error_not_found($slug)->{html};
			} elsif (($args->{recur} // 0) >= 64) {
				$frag .= $self->page->error_max_recursion()->{html};
			} else {
				$frag .= $self->read_partial($filename, $args);
			}
		}

		$text =~ s/$partial_re/$frag/;
	}
	return $text;
}

sub read_partial {
	my ($self, $filename, $args) = @_;
	return '' unless $filename =~ /\.md$/;

	my $chars = Mojo::File->new($filename)->slurp('utf-8');
	my ($yaml, $text) = $self->page->split_frontmatter($chars);

	my %metadata = %{$args->{metadata} // {}};
	delete $metadata{layout};
	my $child_metadata = $yaml ? $self->page->parse_yaml($yaml) : {};
	%metadata = (%metadata, %$child_metadata) if $child_metadata;
	delete $metadata{layout};

	my $new_args = {
		root     => $args->{root},
		filename => $filename,
		recur    => ($args->{recur} // 0) + 1,
		metadata => \%metadata,
	};

	return $self->process($text, $new_args);
}

return 1;
