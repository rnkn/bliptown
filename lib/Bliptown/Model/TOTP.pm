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
	my $totp = $oath->totp($secret);
	my $totp_old = $oath->totp($secret, time - 30);
	return ($totp, $totp_old);
}

sub check_totp {
	my ($self, $args) = @_;
	my $totp = $args->{totp};
	my $totp_expected = ${$args->{totp_expected_pair}}[0];
	my $totp_expected_old = ${$args->{totp_expected_pair}}[1];
	unless (secure_compare($totp, $totp_expected)
			|| secure_compare($totp, $totp_expected_old)) {
		return;
	}
	return 1;
}

return 1;
