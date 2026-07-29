package Bliptown::Model::Token;
use Mojo::Base -base;
use Mojo::Util qw(generate_secret);

has 'db';

sub create_token {
	my ($self, $args)	= @_;
	my $username		= $args->{username} or return;
	my $custom_domain	= $args->{custom_domain} // '';
	my $token			= substr(generate_secret, 0, 40);
	my $expires			= time + 3600;

	my $ok = $self->db->insert(
		'login_tokens', {
			username => $username,
			token => $token,
			custom_domain => $custom_domain,
			expires => $expires,
		}
	);
	return $token if $ok;
}

sub read_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	my $token_rec = $self->db->select(
		'login_tokens', undef, { token => $token }
	)->hash;
	return $token_rec if $token_rec;
}

sub delete_token {
	my ($self, $args) = @_;
	my $token = $args->{token} or return;
	my $ok = $self->db->delete(
		'login_tokens', { token => $token }
	);
	return 1 if $ok;
}

return 1;
