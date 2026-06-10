package FakeIPC;
use Mojo::Base -base;
use Mojo::File qw(path curfile tempfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../../lib');

sub send_message {
	my ($self, $args) = @_;
	my $command = $args->{command} // '';

	my @git_log = ({
		body => 'A  blog/2999-06-08.md',
		date => '2999-06-08 11:03 +0000',
		hash => 'df78309',
		subject => 'Full snapshot on Bliptown'
    },
    {
		body => 'A  blog/2999-05-30.md',
		date => '2999-05-30 10:12 +0000',
		hash => '5fc620b',
		subject => 'Full snapshot on Bliptown'
    },
    {
		body => 'A  blog/2999-05-29.md',
		date => '2999-05-29 21:12 +0000',
		hash => 'aa569c5',
		subject => 'Full snapshot on Bliptown'
    });

	my $filename = $args->{filename} // '';
	my $new_filename = $args->{new_filename} // '';
	my $domain = $args->{domain} // '';

	my %responses = (
		'write_blob'				=> "Wrote file: $filename",
		'update_file'				=> "Updated file: $filename",
		'rename_file'				=> "Renamed file: $filename -> $new_filename",
		'delete_file'				=> "Deleted: $filename",
		'backup_file'				=> "Created backup file: $filename~",
		'make_directory'			=> "Created directory: $filename",
		'git_commit'				=> $git_log[0]->{hash},
		'git_log'					=> \@git_log,
		'git_show'					=> 'commit df783099b67902754eb482aaf01c4eaee922fb33',
		'git_checkout'				=> $git_log[0]->{hash},
		'git_archive'				=> '/tmp/tmp.XXXXXX',
		'provision_cert'			=> "Provisioned certificate: $domain",
		'update_acme_domains'		=> 'ACME domain list up-to-date',
		'update_relayd_keypairs'	=> 'relayd keypairs up-to-date',
	);

	my $res = $responses{$command};
	if ($res) {
		return { info => $res, error => '' };
	}
	else {
		return { info => '', error => "Command not permitted: $command" };
	}
}

return 1;
