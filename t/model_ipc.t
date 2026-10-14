use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use lib curfile->dirname->sibling('lib'), curfile->sibling('lib');
use Test::More;

use BliptownTest;
use FakeIPC;

my $ipc = FakeIPC->new;

subtest 'send_message' => sub {
	my $command = 'invalid';
	my $res = $ipc->send_message({
		command => $command,
	});
	is $res->{error}, "Command not permitted: $command", 'send_message rejects invalid command';
};

done_testing;
