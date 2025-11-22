package Bliptown::Model::File;
use Mojo::Base -base;
use Mojo::File;

sub read_file {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	return unless -r $file;
	my $chars = $file->slurp('utf-8');
	return {
		chars => $chars,
	};
}

return 1;
