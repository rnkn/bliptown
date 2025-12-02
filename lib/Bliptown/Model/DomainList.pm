package Bliptown::Model::DomainList;
use Mojo::Base -base;

has 'sqlite';
has 'ipc';

sub update_domain_list {
	my $self = shift;
	my $coll = $self->sqlite->db->select('users', 'custom_domain')->arrays;
	my @all_domains = @{$coll->flatten};
	@all_domains = grep { defined $_ } @all_domains;
	@all_domains = sort @all_domains;
	$self->ipc->send_message(
		{
			username => 'root',
			command => 'update_domain_list',
			all_domains => \@all_domains
		}
	);
}

return 1;
