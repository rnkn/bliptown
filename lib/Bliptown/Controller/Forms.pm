package Bliptown::Controller::Forms;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Template;

sub submit_form {
	my $c = shift;
	my $username = $c->get_req_username;
	return $c->reply->not_found unless $username;

	my $user_rec = $c->user->read_user({
		key => 'username',
		username => $username,
	});
	return $c->reply->exception("User not found: $username") unless $user_rec;

	my $email_address = $user_rec->{email};
	return $c->reply->exception("User email address not found: $username") unless $email_address;

	if ($c->param('form') eq 'contact') {
		$c->email->send_contact_form({
			recipient_name => $username,
			recipient_email_address => $email_address,
			sender_name => $c->param('name'),
			sender_email_address => $c->param('email'),
			message => $c->param('message'),
		});
	}
	return $c->redirect_to('render_page');
}

return 1;
