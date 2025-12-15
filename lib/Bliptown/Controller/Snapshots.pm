package Bliptown::Controller::Snapshots;
use Mojo::Base 'Mojolicious::Controller';

sub take_snapshot {
	my $c = shift;
	my $username = $c->session('username');

	my $data = $c->ipc->send_message(
		{
			command => 'git_commit',
			username => $username,
		});

	my $hash = $data->{response};
	$c->flash(info => "Snapshot $hash taken");
	return $c->redirect_to('list_snapshots');
}

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
