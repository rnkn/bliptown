package Bliptown::Model::Source;
use Mojo::Base -base;

sub create_source {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	$file->touch;
}

sub read_source {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	return unless -r $file;
	my $chars = $file->slurp('utf-8');

	return {
		chars => $chars,
	};
}

sub update_source {
	my ($self, $args) = @_;
	my $file = $args->{file};
	my $chars = $args->{chars};
	$self->create_source({ file => $file });
	$file->spew($chars, 'utf-8');
}

return 1;
