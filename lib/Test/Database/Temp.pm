package Test::Database::Temp;
## no critic (ControlStructures::ProhibitPostfixControls)

use strict;
use warnings;

# ABSTRACT: Create temporary test databases and run tests in all available ones

# VERSION: generated by DZP::OurPkgVersion

=pod

=encoding utf8

=for stopwords temp database

=over

=cut


=head1 STATUS

This module is currently being developed so changes in the API are possible.


=head1 SYNOPSIS

    use Test2::V0;
    use Test::Database::Temp;
    use DBI;
    Test::Database::Temp->use_all_available(
        build => sub {
            my ($driver) = @_;
            my %params = ( args => {} );
            return \%params;
        },
        init => sub { },
        deinit => sub { },
        do => sub {
            my ($db) = @_;
            my $dbh = DBI->connect( $db->connection_info );
            my ( $db_driver, $db_name) = ($db->driver, $db->name);
            subtest "Testing with $db_driver in db $db_name" => sub {
                my @row_ary;
                my $r = try {
                    @row_ary = $dbh->selectrow_array('SELECT 1+2');
                    1;
                } catch {
                    diag 'Failed to select 1+2';
                };
                is( $row_ary[0], 3, 'returned correct' );

                done_testing;
            };
        },
        demolish => sub { },
    );
    done_testing;


=head1 DESCRIPTION

Test::Database::Temp is an extension to L<Database::Temp>.
It provides a way to easily test several different databases
with the same set of test.

Test::Database::Temp has one main function: C<use_all_available>.
Using this subroutine user can safely test his code
in all available (preconfigured to test site) databases.
The ones which are not available are simply skipped over.

Test::Database::Temp supports all databases available in Database::Temp.

Test::Database::Temp uses L<Log::Any> to produce logging messages.

=cut

use Module::Load qw( load );
use English qw( -no_match_vars ) ;  # Avoids regex performance
use Carp;

use Const::Fast;
use Log::Any;
use Try::Tiny;

use Database::Temp ();

const my @DEFAULT_DRIVERS  => qw( Pg SQLite CSV );
const my $DEFAULT_BASENAME => 'test_database_temp_';

=head1 FUNCTIONS

=cut

=head2 available_drivers

Return a list of available Database::Temp drivers.

If you specify the list of drivers yourself,
then availabity check will only be limited to those
and the available ones will be returned.
If same driver is specified several times,
it will be returned as many times.
The ordering of drivers will not changes.

    my @drivers = Test::Database::Temp->available_drivers( drivers => qw( SQLite SQLite Pg CSV ) );

=cut

sub available_drivers {
    my ($class, %params) = @_;
    my $drivers_specifically_requested;
    if( defined $params{'drivers'} ) {
        $drivers_specifically_requested = 1;
    } else {
        $params{'drivers'} = \@DEFAULT_DRIVERS;
        $drivers_specifically_requested = 0;
    }
    my @available_drivers;
    foreach my $driver (@{ $params{'drivers'} }) {
        my $driver_module = "Database::Temp::Driver::${driver}";
        load $driver_module;

        if( $driver_module->is_available() ) {
            Log::Any->get_logger->infof('Database::Temp driver %s available', $driver);
            push @available_drivers, $driver;
        } else {
            Log::Any->get_logger->infof('Database::Temp driver %s not available', $driver);
        }
    }
    return @available_drivers;
}

=head2 use_all_available

Execute same code with all temporary databases.
This method is partly an extended version of C<Database::Temp->new()>.
Just like with C<Database::Temp->new()>, you can specify subroutines
C<init()> and C<deinit()> to initialize and teardown the databases.
It also has subroutines C<build> and C<demolish>.

Use C<build()> to provide arguments to when C<Database::Temp->new()> is called
and C<demolish()> to clean up after database has been removed if necessary.

You can either go with all available L<Database::Temp> drivers,
or you can specify a list of the wanted drivers. In the latter case,
if any of the wanted drivers is unavailable, subroutine will throw
an exception.

One of the benefits of using B<use_all_available()> is that temporary
databases are created one by one, and deleted immediately after use.

See L</SYNOPSIS> for an example.

=cut

sub use_all_available {
    my ($class, %params) = @_;
    my $drivers_specifically_requested;
    if( defined $params{'drivers'} ) {
        $drivers_specifically_requested = 1;
    } else {
        $params{'drivers'} = \@DEFAULT_DRIVERS;
        $drivers_specifically_requested = 0;
    }

    my $basename = $DEFAULT_BASENAME;
    if( defined $params{'basename'} ) {
        croak "Invalid temp database basename '$params{'basename'}'"
            unless $params{'basename'} =~ m/[[:alnum:]_]{1,}/msx;
        $basename = $params{'basename'};
    }

    foreach my $driver (@{ $params{'drivers'} }) {
        my $name;
        if( defined $params{'name'}) {
            $name = ( $basename . $params{'name'} );
        } else {
            $name = Database::Temp::random_name();
        }

        my %opts;
        $opts{init}     = defined $params{'init'}   ? $params{'init'} : sub { };
        $opts{deinit}   = defined $params{'deinit'} ? $params{'deinit'} : sub { };

        my $db;
        local $EVAL_ERROR = undef;
        my $ok = try {
            my $create_params = { args => {}, };
            $create_params = $params{'build'}->( $driver ) if( $params{'build'} );
            $db = Database::Temp->new(
                driver   => $driver,
                basename => $create_params->{basename} // $basename,
                name     => $create_params->{name}     // $name,
                cleanup  => $create_params->{cleanup}  // 1,
                %opts,
                args     => $create_params->{args}     // { },
            );
            1;
        };
        my $error = $EVAL_ERROR;
        my $e = $error ? $error : 'Unknown';
        if( ! $db && $drivers_specifically_requested ) {
            croak "Could not create a temp database with requested driver '$driver'. Error: $e";
        } elsif( ! $db ) {
            Log::Any->get_logger->infof('Could not create Database::Temp for driver \'%s\'. Error: ', $driver, $e);
            next;
        }
        $params{'do'}->( $db );
        $params{'demolish'}->( $db ) if $params{'demolish'};
    }
    return;
}

1;
