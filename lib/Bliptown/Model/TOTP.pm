package Bliptown::Model::TOTP;
use Mojo::Base -base;
use Authen::OATH;
use MIME::Base32;
use Mojo::Util qw(generate_secret secure_compare);

sub create_secret {
	my $self = shift;
	my $secret = encode_base32(substr(generate_secret, 0, 23));
	return $secret;
}

sub read_totp {
	my ($self, $args) = @_;
	my $secret = decode_base32($args->{totp_secret});
	my $oath = Authen::OATH->new;
	return $oath->totp($secret);
}

sub check_totp {
	my ($self, $args) = @_;
	unless (secure_compare $args->{totp}, $args->{totp_expected}) {
		return;
	}
	return 1;
}

return 1;
