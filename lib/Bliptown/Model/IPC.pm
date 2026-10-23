package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::INET;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(b64_encode);

sub send_message {
	my ($self, $args) = @_;
	my $host = $ENV{BLIPTOWN_HELPER_HOST};
	my $port = $ENV{BLIPTOWN_HELPER_PORT};

	my $client = IO::Socket::INET->new(
		Type => SOCK_STREAM,
		PeerAddr => $host,
		PeerPort => $port,
	) or die "Cannot connect to TCP socket: $host:$port ($!)";

	my %payload = %{$args};
	$payload{data_home} = $ENV{BLIPTOWN_DATA_HOME};
	$payload{blob} = b64_encode(delete $payload{blob}) if defined $payload{blob};

	my $req_json = encode_json(\%payload);
	my $res_json = '';

	$client->send($req_json)	or die "Cannot send data to socket ($!)";
	$client->shutdown(SHUT_WR)	or die "Cannot shutdown socket ($!)";

	while (read($client, my $buf, 512)) {
		$res_json .= $buf;
	}

	$client->close;
	my $res = decode_json($res_json);
	return $res;
}

return 1;
