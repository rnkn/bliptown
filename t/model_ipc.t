use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib'), path(THIS_DIR, 'lib');
use Test::More;

use FakeIPC;

use_ok qw(Bliptown::Model::IPC);

my $ipc = FakeIPC->new;

subtest 'send_message' => sub {
	my $command = 'invalid';
	my $res = $ipc->send_message({
		command => $command,
	});
	is $res->{error}, "Command not permitted: $command", 'send_message rejects invalid command';
};

done_testing;
