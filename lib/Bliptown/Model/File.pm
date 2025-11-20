package Bliptown::Model::File;
use Mojo::Base -base;
use Mojo::File;
use IO::Socket::UNIX;
use Data::MessagePack;

sub read_file {
	my ($self, $args) = @_;
	my $file = Mojo::File->new($args->{file});
	return unless -r $file;
	my $chars = $file->slurp('utf-8');

	return {
		chars => $chars,
	};
}

my $mp = Data::MessagePack->new();

sub update_file {
	my ($self, $args) = @_;
	my $sock_path = '/var/run/bliptown_helper.sock';
	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $sock_path,
	) or die "Cannot connect to socket: $sock_path ($!)";

	my $data = {
		command => $args->{command},
		payload => {
			username => $args->{username},
			filename => $args->{filename},
			new_filename => $args->{new_filename} // '',
			content => $args->{content} // '',
			domains => $args->{domains} // '',
		},
	};

	my $packed_data = $mp->pack($data);

	$client->send($packed_data) || die "Cannot send data to socket ($!)";

	$client->close;
}

return 1;
