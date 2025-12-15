package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::UNIX;
use Sereal::Encoder;
use Sereal::Decoder;

my $encoder = Sereal::Encoder->new;
my $decoder = Sereal::Decoder->new;

$SIG{CHLD} = 'IGNORE';

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
			username		=> $args->{username},
			filename		=> $args->{filename},
			new_filename	=> $args->{new_filename} // '',
			create_backup	=> $args->{create_backup} // 0,
			content			=> $args->{content} // '',
			blob			=> $args->{blob} // '',
			hash			=> $args->{hash} // '',
			domain			=> $args->{domain} // '',
			all_domains		=> $args->{all_domains} // [],
		},
	};

	my $req_blob = $encoder->encode($data);
	my $res_blob;
	$client->send($req_blob) or die "Cannot send data to socket ($!)";

	shutdown($client, 1) or die "Cannot shutdown socket ($!)";

	while (read($client, my $buf, 512)) {
		$res_blob .= $buf;
	}

	$client->close;
	my $res = $decoder->decode($res_blob);
	return $res;
}

return 1;
