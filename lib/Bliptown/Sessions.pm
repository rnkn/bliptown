package Bliptown::Sessions;
use Mojo::Base 'Mojolicious::Sessions';
use Mojo::Util qw(dumper);

sub store {
	my ($self, $c) = @_;

	my $domain = $c->config->{domain};
	my $custom_domain = $c->stash('custom_domain') // '';
	$self->cookie_domain(".$custom_domain") if $custom_domain;
	my $res = $self->SUPER::store($c);
	$self->cookie_domain($domain);

	return $res;
}

return 1;
