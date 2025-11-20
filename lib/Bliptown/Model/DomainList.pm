package Bliptown::Model::DomainList;
use Mojo::Base -base;

has 'sqlite';
has 'file';

sub update_domain_list {
	my $self = shift;
	my $coll = $self->sqlite->db->select('users', 'custom_domain')->arrays;
	my @domains = @{$coll->flatten};
	@domains = grep { defined $_ } @domains;
	@domains = sort @domains;
	$self->file->update_file(
		{ command => 'update_domain_list', domains => \@domains }
	);
}

return 1;
