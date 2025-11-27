package Bliptown::Model::QRCode;
use Mojo::Base -base;
use Imager::QRCode;
use MIME::Base64 qw(encode_base64);
use Mojo::Util qw(dumper);

sub create_qrcode {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my $secret = $args->{secret};
	my $otp_url = "otpauth://totp/Bliptown${username}?secret=${secret}&issuer=blip.town";

	my $qrcode = Imager::QRCode->new();
	my $img = $qrcode->plot($otp_url);
	my $png;
	$img->write(data => \$png, type => 'png') or die $img->errstr;
	my $data = encode_base64($png, '');
	my $data_url = "data:image/png;base64,${data}";

	return $data_url;
}

return 1;
