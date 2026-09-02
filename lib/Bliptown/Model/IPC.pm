package Bliptown::Model::IPC;
use Mojo::Base -base;
use IO::Socket::UNIX;
use Mojo::JSON qw(encode_json decode_json);

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
			user			=> $args->{user}			// '',
			username		=> $args->{username}		// '',
			filename		=> $args->{filename}		// '',
			new_filename	=> $args->{new_filename}	// '',
			create_backup	=> $args->{create_backup}	// 0,
			content			=> $args->{content}			// '',
			blob			=> $args->{blob}			// '',
			hash			=> $args->{hash}			// '',
			domain			=> $args->{domain}			// '',
			domains			=> $args->{domains}			// [],
		},
	};

	my $req_blob = encode_json($data);
	my $res_blob = '';

	$client->send($req_blob)	or die "Cannot send data to socket ($!)";
	$client->shutdown(1)		or die "Cannot shutdown socket ($!)";

	while (read($client, my $buf, 512)) {
		$res_blob .= $buf;
	}

	$client->close;
	my $res = decode_json($res_blob);
	return $res;
}

return 1;
