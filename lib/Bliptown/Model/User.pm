package Bliptown::Model::User;
use Mojo::Base -base;
use Crypt::Bcrypt qw(bcrypt bcrypt_check);

sub get_user {
	my $self = shift;
	my @hostname = split(/\./, $self->req->url->to_abs->host);
	return @hostname >= 3 ? $hostname[-3] : 'mayor';
}

sub create_user {
	my ($self, $args) = @_;
	my $password_hash = bcrypt(
		$args->password, '2b', 12, $ENV{BLIPTOWN_SALT}
	);
	$self->sqlite->db->insert(
		'users', {
			username => $args->username,
			email => $args->email,
			password_hash => $password_hash,
		});
}

sub read_user {
    my ($self, $args) = @_;
    my $data = $self->sqlite->db->select(
		'users', undef, {
			username => $args->username
		})->hash;
}

my @allowed_keys = qw(username email password_hash);

sub update_user {
	my ($self, $args) = @_;
	my $values = {};
	foreach my $key (keys %$args) {
		if (grep { $key eq $_ } @allowed_keys) {
			$values->{$key} = %$args{$key};
		}
	};
    $self->sqlite->db->update('users', { $values }, { id => $args->username });
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
    my $res = $self->read_user({ username => $args->username });
    my $hash = $res->{password_hash};
    if ($hash) {
        return bcrypt_check($args->password, $hash);
    }
    return undef;
}

return 1;
