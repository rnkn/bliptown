package Bliptown::Model::User;
use Mojo::Base -base;
use Crypt::Bcrypt qw(bcrypt bcrypt_check);

sub create_user { }

sub read_user {
    my ($self, $username) = @_;
    my $data = $self->sqlite->db->select('users', undef, { username => $username })->hash;
}

sub update_user { }

sub delete_user { }
