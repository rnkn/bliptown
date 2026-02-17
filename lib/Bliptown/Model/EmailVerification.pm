package Bliptown::Model::EmailVerification;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);

has 'sqlite';

sub create_token {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $token = generate_secret;
	my $expires = time + 24 * 60 * 60; # 24 hours
	$self->sqlite->db->insert(
		'email_verification_tokens', {
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
	my $record = $self->sqlite->db->select(
		'email_verification_tokens', undef, { token => $token }
	)->hash;
	return $record if $record;
	return;
}

sub delete_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	$self->sqlite->db->delete(
		'email_verification_tokens', { token => $token }
	);
	return 1;
}

return 1;
