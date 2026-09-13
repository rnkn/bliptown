package FakeEmail;
use Mojo::Base -base;

has 'sent';

sub send_magic_link {
	my ($self, $args) = @_;
	$self->{sent} //= [];
	push @{$self->{sent}}, $args;
	return 1;
}

return 1;
