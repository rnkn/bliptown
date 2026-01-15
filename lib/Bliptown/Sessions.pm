package Bliptown::Sessions;
use Mojo::Base 'Mojolicious::Sessions';

sub store {
	my ($self, $c) = @_;

	my $custom_domain = $c->stash('custom_domain') // '';
	$self->cookie_domain(".$custom_domain") if $custom_domain;

	return $self->SUPER::store($c);
}

return 1;
