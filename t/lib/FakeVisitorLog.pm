package FakeVisitorLog;
use Mojo::Base -base;

sub new {
	return bless { visits => [] }, shift;
}

sub visits {
	return shift->{visits};
}

sub info {
	my ($self, @args) = @_;
	push @{$self->{visits}}, \@args;
	return;
}

return 1;
