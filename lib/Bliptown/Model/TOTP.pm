package Bliptown::Model::TOTP;
use Mojo::Base -base;
use Authen::OATH;
use MIME::Base32;

sub create_totp {
	my $self = shift;
	my @base64_set = (0 .. 9, 'a' .. 'z', 'A' .. 'Z', '+', '/');
	my $rand_str = join '', map $base64_set[rand @base64_set], 0 .. 21;
	my $secret = encode_base32 $rand_str;
	return $secret;
}

sub read_totp {
	my ($self, $args) = @_;
	my $secret = decode_base32 $args->{totp_secret};
	my $oath = Authen::OATH->new;
	return $oath->totp($secret);
}

return 1;
