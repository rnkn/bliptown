package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::UNIX;
use Sereal::Encoder;

my $encoder = Sereal::Encoder->new;

sub send_message {
	my ($self, $args) = @_;
	my $sock_path = $ENV{BLIPTOWN_HELPER_SOCKET};
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
			create_backup => $args->{create_backup} // 0,
			content => $args->{content} // '',
			blob => $args->{blob} // '',
			domain => $args->{domain} // '',
			all_domains => $args->{all_domains} // [],
		},
	};

	my $blob = $encoder->encode($data);
	$client->send($blob) || die "Cannot send data to socket ($!)";
	$client->close;
}

return 1;
