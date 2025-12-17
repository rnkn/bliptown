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

	my $res_hash = $data->{response};
	$c->flash(info => "Snapshot $res_hash taken");
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
		repo => "${username}\@blip.town:www",
	);
	return $c->render;
}

sub restore_snapshot {
	my $c = shift;
	my $username = $c->session('username');
	my $hash = $c->param('hash');

	my $data = $c->ipc->send_message(
		{
			command => 'git_checkout',
			username => $username,
			hash => $hash,
		});

	my $res_hash = $data->{response};
	$c->flash(info => "Snapshot $res_hash restored");
	return $c->redirect_to($c->url_for('list_files')->query(filter => "snapshots/$res_hash"));
}

return 1;
