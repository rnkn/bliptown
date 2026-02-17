package Bliptown::Model::PaymentToken;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);

has 'sqlite';

sub create_token {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $token = generate_secret;
	my $created = time;
	$self->sqlite->db->insert(
		'payment_tokens', {
			username => $username,
			token => $token,
			created => $created,
		}
	);
	return $token;
}

sub read_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	my $record = $self->sqlite->db->select(
		'payment_tokens', undef, { token => $token }
	)->hash;
	return $record if $record;
	return;
}

sub delete_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	$self->sqlite->db->delete(
		'payment_tokens', { token => $token }
	);
	return 1;
}

return 1;
