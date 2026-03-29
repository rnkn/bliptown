package Geo::Location::IP::Database::Reader;
use Mojo::Base -base;

# Stub module for testing - replaces the real Geo::Location::IP::Database::Reader
# which requires a MaxMind GeoIP database file to be present.

sub new {
	my ($class, %args) = @_;
	return bless {}, $class;
}

sub country {
	my ($self, %args) = @_;
	return undef;
}

return 1;
