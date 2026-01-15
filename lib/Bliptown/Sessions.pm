package Bliptown::Sessions;
use Mojo::Base 'Mojolicious::Sessions';

sub store {
	my ($self, $c) = @_;

	my $custom_session_domain = $c->stash('custom_session_domain');
	$self->cookie_domain(".$custom_session_domain") if $custom_session_domain;

	return $self->SUPER::store($c);
}

return 1;
