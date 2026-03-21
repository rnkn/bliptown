package Bliptown::Model::Metadata;
use Mojo::Base -base;
use YAML::Tiny;

sub read_metadata {
	my ($self, $yaml) = @_;
	my $yaml_obj = YAML::Tiny->new;
	my $metadata = eval { $yaml_obj->read_string($yaml)->[0] } // {};
	return $metadata;
}

return 1;
