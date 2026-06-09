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
	my $encoded_secret = $args->{totp_secret};
	return unless $encoded_secret;
	my $secret = decode_base32($encoded_secret);
	my $time = $args->{time} // time;
	my $oath = Authen::OATH->new;
	my $totp = $oath->totp($secret, $time);
	my $totp_old = $oath->totp($secret, $time - 30);
	return ($totp, $totp_old);
}

sub check_totp {
	my ($self, $args) = @_;
	my $totp = $args->{totp};
	return unless $args->{totp_expected_pair};
	my @expected_totp_pair = @{$args->{totp_expected_pair}};
	my $totp_expected = $expected_totp_pair[0];
	my $totp_expected_old = $expected_totp_pair[1];
	unless (secure_compare($totp, $totp_expected)
			|| secure_compare($totp, $totp_expected_old)) {
		return;
	}
	return 1;
}

return 1;
