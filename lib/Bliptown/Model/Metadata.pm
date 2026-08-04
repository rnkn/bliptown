package Bliptown::Model::Metadata;
use Mojo::Base -base;
use YAML::Tiny;

sub read_metadata {
	my ($self, $yaml) = @_;
	my $y = YAML::Tiny->new;
	my $metadata = eval { $y->read_string($yaml)->[0] } // {};
	return $metadata;
}

return 1;
