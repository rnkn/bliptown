package Bliptown::Model::Mustache;
use Mojo::Base -base;
use Mojo::File;
use POSIX qw(strftime);

has 'user';
has 'metadata';
has 'util';
has 'prettydate_fmt';

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

sub process_prettydate {
	my ($self, $date) = @_;
	my ($year, $month, $day) = $date =~ /([0-9]{4})-([0-9]{2})-([0-9]{2})/;
	$year = $year - 1900;
	$month--;
	my $fmt = $self->prettydate_fmt;
	return strftime($fmt, 0, 0, 0, $day, $month, $year) // '';
}

sub process_variables {
	my ($self, $text, $args) = @_;
	my $metadata = $args->{metadata};
	my $variable_re = qr/\{\{\ *([[:alnum:]\ _-]+?)\ *\}\}/;

	while ($text =~ $variable_re) {
		my $key = $1;
		my $val;
		my $date = $metadata->{date};

		if ($date && $key eq 'prettydate') {
			$val = $self->process_prettydate($date);
		}
		else {
			$val = $metadata->{$key} // '';
		}
		$text =~ s/$variable_re/$val/;
	}
	return $text;
}

sub process_sections {
	my ($self, $text, $args) = @_;
	my $section_re = qr/\{\{\ *#\ *([^\n]+?)\ *\}\}\n(.*?)\n?\{\{\ *\/\ *\}\}/s;

	while ($text =~ $section_re) {
		my ($glob, $template) = ($1, $2);
		my @filenames = $self->util->glob_path($glob, $args->{root}, $args->{filename});

		my @items;
		foreach my $filename (@filenames) {
			next unless -f $filename;
			my $chars = Mojo::File->new($filename)->slurp('UTF-8');
			my ($yaml, undef) = $self->util->split_frontmatter($chars);
			my $metadata = $yaml ? $self->metadata->read_metadata($yaml) : {};
			my %item_metadata = %$metadata;
			next unless %item_metadata && $item_metadata{date};

			my %parent_metadata = %{$args->{metadata}};
			%item_metadata = (%parent_metadata, %item_metadata);
			$item_metadata{url} = $self->util->filename_to_slug($filename, $args->{root});

			push @items, \%item_metadata;
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
	my $partial_re = qr/\{\{\ *>\ *(.+?)\ *\}\}/;

	while ($text =~ $partial_re) {
		my $slug = $1;
		my @filenames = $self->util->glob_path($slug, $args->{root}, $args->{filename});

		my $partial = '';
		my @partials;
		foreach my $filename (@filenames) {
			if (!-f $filename) {
				$partial = $self->error_not_found($slug);
			}
			elsif (($args->{recur} // 0) >= 64) {
				$partial = $self->error_max_recursion;
			}
			else {
				$partial = $self->read_partial($filename, $args);
			}
			push @partials, $partial if $partial;
		}

		@partials = @{$self->collect_partials(\@partials)} if scalar @partials > 1;
		$partial = join "\n", map { $_->{text} } @partials;
		$text =~ s/$partial_re/$partial/;
	}
	return $text;
}

sub collect_partials {
	my ($self, $partial_list_ref) = @_;
	my @partials = @$partial_list_ref;
	@partials = grep { defined $_->{metadata}->{date} } @partials;
	@partials = sort { $b->{metadata}->{date} cmp $a->{metadata}->{date} } @partials;
	map { $_->{text} = <<"EOF"
<div class="blog-post">

$_->{text}

</div>
EOF
	} @partials;
	return \@partials;
}

sub error_not_found {
	my ($self, $slug) = @_;
	my $html = <<"EOF";
<p class="error">Error 404: "<a href="$slug">$slug</a>" not found</p>
EOF
	return {
		metadata => {
			title => 'Bliptown :: Error 404: File Not Found',
			status => 404,
		},
		text => $html
	}
}

sub error_max_recursion {
	my ($self) = @_;
	my $html = <<'EOF';
<span class="error">Error 508: exceeded maximum level of recursion</span>
EOF
	return {
		metadata => {
			title => 'Bliptown :: Error 508: Recursion',
			status => 508,
		},
		text => $html
	};
}

sub read_partial {
	my ($self, $filename, $args) = @_;
	return unless $filename =~ /\.md$/;

	my $chars = Mojo::File->new($filename)->slurp('UTF-8');
	my ($yaml, $text) = $self->util->split_frontmatter($chars);

	my %metadata = %{$args->{metadata}};
	delete $metadata{layout};
	my $child_metadata = $yaml ? $self->metadata->read_metadata($yaml) : {};
	$child_metadata->{url} = $self->util->filename_to_slug($filename, $args->{root});
	%metadata = (%metadata, %$child_metadata) if $child_metadata;

	my $child_args = {
		root     => $args->{root},
		filename => $filename,
		recur    => ($args->{recur} // 0) + 1,
		metadata => \%metadata,
	};

	return {
		text => $self->process($text, $child_args),
		metadata => \%metadata
	}
}

return 1;
