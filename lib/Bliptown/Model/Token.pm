package Bliptown::Model::Token;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);

has 'db';

sub create_token {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $token = generate_secret;
	my $expires = time + 30;
	$self->db->insert(
		'login_tokens', {
			username => $username,
			token => $token,
			expires => $expires,
		}
	);
	return $token;
}

sub read_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	my $record = $self->db->select(
		'login_tokens', undef, { token => $token }
	)->hash;
	return $record if $record;
	return;
}

sub delete_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	$self->db->delete(
		'login_tokens', { token => $token }
	);
	return 1;
}

return 1;
