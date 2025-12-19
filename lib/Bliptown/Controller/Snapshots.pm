package Bliptown::Controller::Snapshots;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Asset::File;

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
		repo => "${username}\@blip.town:site",
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

sub download_snapshot {
	my $c = shift;
	my $username = $c->session('username');
	my $hash = $c->param('hash');

	my $data = $c->ipc->send_message(
		{
			command => 'git_archive',
			username => $username,
			hash => $hash,
		});

	my $filename = $data->{response};
	my $asset = Mojo::Asset::File->new(path => $filename);

	$c->res->headers->content_type('application/gzip');
	$c->res->headers->content_disposition(
		"attachment; filename=${username}.blip.town-${hash}.tar.gz"
	);

	$c->on(
		finish => sub {
			$c->ipc->send_message(
				{
					command => 'delete_file',
					username => $username,
					filename => $filename,
				}
			)
		});

	return $c->reply->asset($asset);
}

return 1;
