package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::UNIX;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::Util qw(b64_encode);

sub send_message {
	my ($self, $args) = @_;
	my $sock_path = $ENV{BLIPTOWN_HELPER_SOCKET};

	my $client = IO::Socket::UNIX->new(
		Type => SOCK_STREAM,
		Peer => $sock_path,
	) or die "Cannot connect to socket: $sock_path ($!)";

	my $b64_encoded = b64_encode($args->{blob}) if length $args->{blob};

	my $data = {
		command => $args->{command},
		payload => {
			system_user		=> $args->{system_user}		// '',
			username		=> $args->{username}		// '',
			filename		=> $args->{filename}		// '',
			new_filename	=> $args->{new_filename}	// '',
			create_backup	=> $args->{create_backup}	// 0,
			content			=> $args->{content}			// '',
			blob			=> $b64_encoded				// '',
			hash			=> $args->{hash}			// '',
			domain			=> $args->{domain}			// '',
			domains			=> $args->{domains}			// [],
		},
	};

	my $req_json = encode_json($data);
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
