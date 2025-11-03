package Bliptown::Model::User;
use Mojo::Base -base;
use Mojo::Util qw(secure_compare);
use Crypt::Bcrypt qw(bcrypt bcrypt_check);
use MIME::Base32;
use Authen::OATH;

has 'sqlite';

sub get_user {
	my $self = shift;
	my @hostname = split(/\./, $self->req->url->to_abs->host);
	return @hostname >= 3 ? $hostname[-3] : 'mayor';
}

sub create_user {
	my ($self, $args) = @_;
	my $password_hash = bcrypt(
		$args->{password}, '2b', 12, $ENV{BLIPTOWN_SALT}
	);
	my @base64_set = (0 .. 9, 'a' .. 'z', 'A' .. 'Z', '+', '/');
	my $rand_str = join '', map $base64_set[rand @base64_set], 0 .. 21;
	my $secret = encode_base32 $rand_str;
	$self->sqlite->db->insert(
		'users', {
			email => $args->{email},
			username => $args->{username},
			password_hash => $password_hash,
			totp_secret => $secret,
		}
	);
}

sub read_user {
    my ($self, $args) = @_;
	my $key = $args->{username} ? 'username' : $args->{email} ? 'email' : undef;
	return unless $key;

	my $user = $self->sqlite->db->select(
		'users', undef, {
			$key => $args->{$key},
		})->hash;
	return $user if $user;
	return;
}

my @allowed_keys = qw(username email password_hash totp_secret
custom_domain create_backups sort_new);

sub update_user {
	my ($self, $args) = @_;
	my %values;
	foreach my $key (keys %$args) {
		if (grep { $key eq $_ } @allowed_keys) {
			$values{$key} = %$args{$key};
		}
	};
    $self->sqlite->db->update('users', \%values, { username => $args->{username} });
}

sub delete_user {
	my ($self, $args) = @_;
    $self->pg->db->delete(
		'users', {
			username => $args->username,
		});
}

sub authenticate_user {
    my ($self, $args) = @_;
    my $user = $self->read_user({ username => $args->{username} });
	return unless $user;
    my $hash = $user->{password_hash};
	unless ($hash && bcrypt_check($args->{password}, $hash)) {
		return;
    }
	my $secret = decode_base32 $user->{totp_secret};
	my $oath = Authen::OATH->new;
	unless ($secret && secure_compare $oath->totp($secret), $args->{totp}) {
		return;
    }
    return 1;
}

return 1;
