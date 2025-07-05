package Bliptown::Model::Page;
use Mojo::Base -base;
use YAML::Tiny;
use Text::Markdown;

sub read_page {
	my ($self, $args) = @_;
	my $file = $args->{file};
	return unless -r $file;
	my $chars = $file->slurp('utf-8');

	my ($yaml, $metadata, $html, $text);

	if ($chars =~ /^(---.*?---)\s*(.*)$/s) {
		$yaml =$1;
		$text = $2;
	} else {
		$text = $chars;
	}

	if ($yaml) {
		my $obj = YAML::Tiny->new;
		$metadata = $obj->read_string($yaml);
		$metadata = $metadata->[0];
	}

	if ($text) {
		my $obj = Text::Markdown->new;
		$html = $obj->markdown($text);
	}

	return {
		metadata => $metadata,
		html => $html,
	};
}

return 1;
