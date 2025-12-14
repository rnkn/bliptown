package Bliptown::Controller::Snapshots;
use Mojo::Base 'Mojolicious::Controller';

sub list_snapshots {
	my $c = shift;
	my $username = $c->session('username');

	my $data = $c->ipc->send_message(
		{
			command => 'git_log',
			username => $username,
		});

	my $snapshots = $data->{response};

	$c->stash(
		template => 'snapshots',
		title => 'Snapshots',
		show_sidebar => 1,
		snapshots => $snapshots,
	);
	return $c->render;
}

return 1;
