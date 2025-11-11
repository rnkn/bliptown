package Bliptown::Model::File;
use Mojo::Base -base;
use Mojo::File;
use IO::Socket::UNIX;
use Storable qw(store_fd);

sub read_file {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	return unless -r $file;
	my $chars = $file->slurp('utf-8');

	return {
		chars => $chars,
	};
}

sub update_file {
	my ($self, $args) = @_;
	my $sock_path = '/tmp/bliptown_helper.sock';
	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $sock_path,
	) or die "Cannot connect to socket: $sock_path ($!)";

	my $data = {
		command => $args->{command},
		payload => {
			user => $args->{user},
			file => $args->{file},
			new_name => $args->{new_name} // '',
			content => $args->{content} // '',
		},
	};

	store_fd($data, $client);

	$client->close;
}

return 1;
