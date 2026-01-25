package Bliptown::Controller::Snapshots;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Asset::File;

sub take_snapshot {
	my $c = shift;
	my $username = $c->session('username');

	my $res = $c->ipc->send_message(
		{
			command => 'git_commit',
			username => $username,
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	my $res_hash = $res->{response};
	if ($res_hash) {
		$c->flash(info => "Snapshot $res_hash taken");
	} else {
		$c->flash(info => "No changes to snapshot");
	}
	return $c->redirect_to('list_snapshots');
}

sub list_snapshots {
	my $c = shift;
	my $username = $c->session('username');

	my $res = $c->ipc->send_message(
		{
			command => 'git_log',
			username => $username,
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	my $snapshots = $res->{response};
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

	my $res = $c->ipc->send_message(
		{
			command => 'git_checkout',
			username => $username,
			hash => $hash,
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	my $res_hash = $res->{response};
	$c->flash(info => "Snapshot $res_hash restored");
	return $c->redirect_to($c->url_for('list_files')->query(filter => "snapshots/$res_hash"));
}

sub download_snapshot {
	my $c = shift;
	my $username = $c->session('username');
	my $hash = $c->param('hash');

	my $res = $c->ipc->send_message(
		{
			command => 'git_archive',
			username => $username,
			hash => $hash,
		});

	return $c->reply->exception($res->{error}) if $res->{error};

	my $filename = $res->{response};
	my $asset = Mojo::Asset::File->new(path => $filename);

	$c->res->headers->content_type('application/gzip');
	$c->res->headers->content_disposition(
		"attachment; filename=${username}.blip.town-${hash}.tar.gz"
	);

	$c->on(
		finish => sub {
			my $res = $c->ipc->send_message(
				{
					command => 'delete_file',
					username => $username,
					filename => $filename,
				}
			);
			return $c->log->error($res->{error}) if $res->{error};
		});

	return $c->reply->asset($asset);
}

sub diff_snapshot {
	my $c = shift;
	my $username = $c->session('username');
	my $hash = $c->param('hash');

	my $res = $c->ipc->send_message(
		{
			command => 'git_show',
			username => $username,
			hash => $hash,
		}
	);
	return $c->reply->exception($res->{error}) if $res->{error};

	my $diff = $res->{response};
	return $c->render(
		text => $diff,
		format => 'txt',
	);
}

return 1;
