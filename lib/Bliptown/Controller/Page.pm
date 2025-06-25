package Bliptown::Controller::Page;
use Mojo::Base 'Mojolicious::Controller';

sub render_page {
	my $c = shift;
	my @hostname = split('.', $c->req->url->to_abs->host);
	my $user = $hostname[-3] if @hostname >= 3;
	my $path = $c->param('path') || 'index';
	$c->stash(
		template => 'default',
	);
	return $c->render;
}

return 1;
