package Bliptown::Model::Token;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);

sub create_token {
	my ($self, $args) = @_;
	my $username = $args->{username} or return;
	my $token = generate_secret;
	my $expires = time + 30;
	$self->sqlite->db->insert(
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
	my $username = $args->{username} or return;
	my $record = $self->sqlite->db->select(
		'login_tokens', undef, { token => $token }
	)->hash;
	if ($record->{expires} <= time) {
		$self->token->delete_token({ token => $token });
	}
	my $token_username = $record->{username} or return;
	return $token if $token_username eq $username;
}

sub delete_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	$self->sqlite->db->delete(
		'login_tokens', { token => $token }
	);
	return 1;
}

return 1;
