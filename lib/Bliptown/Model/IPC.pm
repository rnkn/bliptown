package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::UNIX;
use Data::MessagePack;

my $mp = Data::MessagePack->new();

sub send_message {
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
			blob => $args->{blob} // '',
			new_filename => $args->{new_filename} // '',
			content => $args->{content} // '',
			domain => $args->{domain} // '',
			all_domains => $args->{all_domains} // [],
		},
	};

	my $packed_data = $mp->pack($data);
	$client->send($packed_data) || die "Cannot send data to socket ($!)";
	$client->close;
}

return 1;
