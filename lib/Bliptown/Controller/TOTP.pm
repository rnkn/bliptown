package Bliptown::Controller::TOTP;
use Mojo::Base 'Mojolicious::Controller';

sub totp_update {
	my $c = shift;
	my $secret = $c->param('secret');
	my $totp = $c->param('totp');
	my $redirect = $c->param('back_to') // '/';
	my $username = $c->session('username');
	my $totp_check = $c->totp->read_totp({ totp_secret => $secret });
	unless ($c->totp->check_totp({ totp => $totp, totp_check => $totp_check})) {
		$c->flash(warning => 'TOTP incorrent');
		return $c->redirect_to('totp_initiate');
	}
	$c->user->update_user(
		{
			username => $username,
			totp_secret => $secret
		});
	return $c->redirect_to($redirect);
}

sub totp_initiate {
	my $c = shift;
	my $username = $c->session('username');
	my $secret = $c->totp->create_secret;
	my $locked = $username eq 'demo' ? 1 : 0;
	my $data_url = $c->qrcode->create_qrcode(
		{
			username => $username,
			secret => $secret,
		}
	);
	$c->stash(
		template => 'totp',
		title => 'Bliptown Two-Factor Authentication',
		locked => $locked,
		secret => $secret,
		data_url => $data_url,
	);
	return $c->render;
}

return 1;
