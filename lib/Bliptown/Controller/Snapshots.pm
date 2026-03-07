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
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $res_hash = $res->{info};
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
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $snapshots = $res->{info};
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
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $res_hash = $res->{info};
	$c->flash(info => "Snapshot $res_hash restored");
	return $c->redirect_to($c->url_for('list_files')->query(search => "snapshots/$res_hash"));
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
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $filename = $res->{info};
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

sub diff_to_html {
	my $chars = shift;
	my $html = '';
	$chars =~ s/&/&amp;/g;
	$chars =~ s/</&lt;/g;
	$chars =~ s/>/&gt;/g;

	for my $line (split /\n/, $chars) {
        if ($line =~ /^( |--[- ]$)/) {
			$html .= "$line\n";
		}
        elsif ($line =~ /^@@/) {
            $html .= qq{<span class="hunk-header">$line</span>\n};
        }
		elsif ($line =~ /^\+/) {
            $html .= qq{<span class="addition">$line</span>\n};
        }
		elsif ($line =~ /^-/) {
            $html .= qq{<span class="deletion">$line</span>\n};
        }
		else {
            $html .= qq{<span class="meta">$line</span>\n};
        }
    }

	$html = <<"EOF";

<section class="wide">
	<pre class="diff">$html</pre>
</section>

EOF
	return $html;
}

sub render_diff {
	my $c = shift;
	my $hash = $c->param('hash');
	my $username = $c->session('username');

	my $res = $c->ipc->send_message(
		{
			command => 'git_show',
			username => $username,
			hash => $hash,
		}
	);
	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	my $diff = $res->{info};

	my $html = diff_to_html($diff);

	$c->stash(
		template => 'diff',
		title => "Snapshot $hash",
		content => $html
	);
	return $c->render;
}

return 1;
