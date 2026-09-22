package Bliptown::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::URL;
use Mojo::File qw(path);

sub validate_user {
	my ($c, $args) = @_;
	my $v = $c->validation;
	$v->required($args->{username})->like(q/[a-zA-Z][a-zA-Z0-9_-]*$/)->size(1,31);
	$v->required($args->{email})->like(q/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)->size(1,254);
	$v->required($args->{password})->size(8,256);
	return 1 unless $v->has_error;
}

sub user_join {
	my $c = shift;
	my $email = $c->param('email') || '';
	my $username = $c->param('username') || '';
	my $password = $c->param('password') || '';
	my $redirect = $c->param('back_to') || '/';

	my %creds = (
		email => $email,
		username => $username,
		password => $password
	);
	unless ($c->validate_user(\%creds)) {
		$c->flash(info => 'Invalid credentials');
		return $c->redirect_to($redirect);
	}

	if ($c->user->read_user({ key => 'username', username => $username })) {
		$c->flash(info => 'Username already in use');
		return $c->redirect_to($redirect);
	}

	if ($c->user->read_user({ key => 'email', email => $email })) {
		$c->flash(info => 'Account with that email already exists');
		return $c->redirect_to($redirect);
	}

	my $ok = $c->user->create_user({
		username => $username,
		email => $email,
		password => $password,
	});

	return $c->reply->exception("Failed to create user in database: $username")
		unless $ok;

	my $res = $c->ipc->send_message({
		command => 'add_user',
		system_user => 'root',
		username => $username,
	});

	return $c->reply->exception($res->{error}) if $res->{error};
	$c->log->debug($res->{info}) unless $c->app->mode eq 'production';

	return $c->redirect_to($redirect);
}

sub generate_login {
	my $c = shift;
	my $username = $c->param('username');
	my $redirect = $c->param('back_to') // '/';
	return unless $username;

	if ($username eq $ENV{BLIPTOWN_DEMO_USER}) {
		$c->session(username => $ENV{BLIPTOWN_DEMO_USER});
		return $c->redirect_to($redirect);
	}

	my $user = $c->user->read_user({
		key => 'username',
		username => $username,
	});

	unless ($user) {
		return $c->render(
			status => 404,
			template => 'message',
			page_title => 'Not Found',
			content => 'User not found.',
		);
	}

	my $cooldown = 600;
	my @recent = $c->token->read_recent_login_tokens({
		username => $username
	})->each;

	if (scalar @recent >= 3) {
		my $created = $recent[0]->{expires} - 3600;
		if (time - $created < $cooldown) {
			return $c->render(
				status => 429,
				template => 'message',
				page_title => 'Too Many Requests',
				content => 'Too many login attempts for that user. Please try again in a moment.'
			);
		};
	}

	my $email = $user->{email};
	return $c->reply->exception("No email associated with username $username") unless $email;

	my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_domain.txt');
	my $custom_domain = -f $path ? $c->util->read_file_line($path) : '';

	$c->email->send_magic_link({
		username => $username,
		email => $email,
		custom_domain => $custom_domain,
	});
	return $c->redirect_to('user_login');
}

sub user_login {
	my $c = shift;
	$c->render(
		template => 'message',
		page_title => 'Login',
		content => 'Check your email for a login link. You can now close this window.',
	);
}

sub user_auth {
	my $c = shift;
	my $token = $c->param('token') // '';
	my $redirect = $c->param('back_to') // '/';

	my $host = $c->req->url->to_abs->host;
	return unless $host;
	$host =~ s/^www\.//;

	my $token_rec = $c->token->read_login_token({ token => $token });
	
	unless ($c->token->validate_login_token_rec({ token_rec => $token_rec })) {
		return $c->render(
			status => 403,
			template => 'message',
			page_title => 'Forbidden',
			content => 'Sorry, that token is invalid or expired.',
		);
	}

	my $username = $token_rec->{username};
	my $custom_domain = $token_rec->{custom_domain};

	$c->session(expiration => 30 * 24 * 60 * 60, username => $username);

	if ($custom_domain) {
		if ($host eq $custom_domain) {
			$c->session(expiration => 30 * 24 * 60 * 60, username => $username);
			$c->token->delete_login_token({ token => $token });
			return $c->redirect_to('/');
		}
		else {
			my $url = Mojo::URL->new;
			$url->host($custom_domain);
			$url->scheme($ENV{BLIPTOWN_SCHEME});
			$url->port($ENV{BLIPTOWN_PORT});
			$url->path($c->url_for('user_auth'));
			$url->query(token => $token);
			return $c->redirect_to($url);
		}
	}
	else {
		$c->token->delete_login_token({ token => $token });
		return $c->redirect_to($redirect);
	}
}

sub generate_logout {
	my $c = shift;
	my $username = $c->session('username');
	return $c->redirect_to('/') unless $username;
	my $redirect = $c->param('back_to');
	my $custom_domain = $c->get_user_custom_domain($username);

	my $token;
	if ($custom_domain) {
		$token = $c->token->create_logout_token({
			username => $username,
			custom_domain => $custom_domain,
		});
	}

	my $url = $c->util->create_bliptown_url({
		path => $c->url_for('user_logout'),
		token => $token,
		redirect => $redirect,
	});

	return $c->redirect_to($url);
}

sub user_logout {
	my $c = shift;
	my $token = $c->param('token') // '';
	my $redirect = $c->param('back_to') // '/';

	my $host = $c->req->url->to_abs->host;
	$host =~ s/^www\.//;

	$c->session(expires => 1);

	my $token_rec = $c->token->read_logout_token({ token => $token });
	my $custom_domain = $token_rec->{custom_domain} if $token_rec;

	if ($custom_domain) {
		if ($host eq $custom_domain) {
			my $url = $c->create_bliptown_url({
				path => $c->url_for('user_logout'),
				redirect => $redirect,
			});
			return $c->redirect_to($url);
		}
		else {
			my $url = $c->util->create_bliptown_url({
				host => $custom_domain,
				path => $c->url_for('user_logout'),
				redirect => $redirect,
			});
			return $c->redirect_to($url);
		}
	}

	return $c->redirect_to($redirect);
}

sub billing_session {
	my $c = shift;
	my $customer_id = $c->param('customer_id');

	my $billing_session = $c->customer->create_billing_session({
		customer_id => $customer_id
	});
	return $c->reply->exception("Cannot create billing sessions for customer_id $customer_id")
		unless $billing_session;

	my $billing_portal_url = $billing_session->{url};
	return $c->reply->exception("Cannot create billing portal URL for customer_id $customer_id")
		unless $billing_portal_url;

	return $c->redirect_to($billing_portal_url);
}

return 1;
