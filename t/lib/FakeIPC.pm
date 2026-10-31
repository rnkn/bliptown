package FakeIPC;
use Mojo::Base -base;
use Mojo::File qw(path curfile tempfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../../lib');

sub send_message {
	my ($self, $args) = @_;
	my $command		= $args->{command}	// '';
	my $username	= $args->{username} // '';
	my $hash		= $args->{hash}		// '';

	my @git_log = ({
		body	=> 'A  blog/2999-06-08.md',
		date	=> '2999-06-08 11:03 +0000',
		hash	=> 'df78309',
		subject => 'Full snapshot on Bliptown'
    },
    {
		body	=> 'A  blog/2999-05-30.md',
		date	=> '2999-05-30 10:12 +0000',
		hash	=> '5fc620b',
		subject => 'Full snapshot on Bliptown'
    },
    {
		body	=> 'A  blog/2999-05-29.md',
		date	=> '2999-05-29 21:12 +0000',
		hash	=> 'aa569c5',
		subject => 'Full snapshot on Bliptown'
    });

	my $system_user		= $args->{system_user}	// '';
	my $filenames		= $args->{filenames}	// [];
	my $domain			= $args->{domain}		// '';

	# Only dereference as hashes when the elements are hashes; delete_files
	# sends plain filenames in the same key
	my $rename_info = $command eq 'rename_files'
		? join(', ', map { "Renamed file: $_->{old} -> $_->{new}" } @{$filenames})
		: '';

	my %responses = (
		'write_blob'				=> "Wrote file: $filenames->[0]",
		'update_file'				=> "Updated file: $filenames->[0]",
		'rename_files'				=> $rename_info,
		'delete_files'				=> 'Deleted: ' . join(', ', @{$filenames}),
		'backup_file'				=> "Created backup file: $filenames->[0]~",
		'make_directory'			=> "Created directory: $filenames->[0]",
	);

	my @git_hash_commands = qw(git_show git_checkout git_archive);

	if (grep { $command eq $_ } @git_hash_commands) {
		unless (grep { $hash eq $_ } map { $_->{hash} } @git_log) {
			return { info => '', error => "Invalid hash: $hash" }
		}
	}
	
	my $res = $responses{$command};
	if ($res) {
		return { info => $res, error => '' };
	}
	else {
		return { info => '', error => "Command not permitted: $command" };
	}
}

return 1;
