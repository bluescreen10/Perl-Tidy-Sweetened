package Perl::Tidy::Sweetened::Keyword::SubSignature;

# ABSTRACT: Perl::Tidy::Sweetened filter plugin to define new subroutine keywords

use 5.010;    # Needed for balanced parens matching with qr/(?-1)/
use strict;
use warnings;
use Carp;

our $VERSION = '0.20';

# Regex to match balanced parans. Reproduced from Regexp::Common to avoid
# adding a non-core dependency.
#   $RE{balanced}{-parens=>'()'};
# The (?-1) construct requires 5.010
our $Paren = '(?:((?:\((?:(?>[^\(\)]+)|(?-1))*\))))';

sub new {
    my ( $class, %args ) = @_;
    croak 'keyword not specified' if not exists $args{keyword};
    croak 'marker not specified'  if not exists $args{marker};
    $args{clauses} = [] unless exists $args{clauses};
    return bless {%args}, $class;
}

sub keyword { return $_[0]->{keyword} }
sub marker  { return $_[0]->{marker} }

sub emit_sub {
    my ( $self, $subname, $brace, $clauses ) = @_;

    # Store the signature and returns() for later use
    my $id = $self->{counter}++;

    # $self->{store}->{$id} = { signature => $signature, returns => $returns };

    $self->{store}->{$id} = $clauses;

    return sprintf 'sub %s %s #__%s %s', $subname, $brace, $self->marker, $id;
}

sub emit_keyword {
    my ( $self, $subname, $brace, $id ) = @_;

    # Get the signature and returns() from store
    my $clauses = $self->{store}->{$id};

    # Combine clauses (parameter list, returns(), etc) into a string separate
    # each with a space and lead with a space if there are any
    my $clause = join ' ', grep { length $_ } @$clauses;
    $clause = ' ' . $clause if length $clause;

    return sprintf '%s %s%s%s', $self->keyword, $subname, $clause, $brace;
}

sub clauses {
    my $self = shift;

    # Create a regex (as a string) for all the clauses (ie, parameter list,
    # returns(), etc).
    my $clause_re = '';
    my $i         = 0;
    for my $clause ( @{ $self->{clauses} } ) {
        $clause =~ s{PAREN}{$Paren}g;

        $clause_re .= "(?<clause_$i>  $clause ) \\s* \n";
        $i++;
    }

    return $clause_re;
}
$|++;

sub prefilter {
    my ( $self, $code ) = @_;
    my $keyword = $self->keyword;

    $code =~ s{
        ^\s*\K                    # okay to have leading whitespace (preserve)
        $keyword             \s+  # the "func/method" keyword
        (?<subname> \w+)     \s*  # the function name
        @{[ $self->clauses ]}     # any clauses defined (ie, a parameter list)
        (?<brace> .*?)            # anything else (ie, comments) including brace
        $
    }{
        my $i = 0;
        my $clauses = [];
        while( exists $+{"clause_$i"} ){
            warn "# clause_$i: " . $+{"clause_$i"} . "\n";
            push @$clauses, $+{"clause_$i"};
            $i++;
        }
        $self->emit_sub( $+{subname}, $+{brace}, $clauses )
    }egmx;

    return $code;
}

sub postfilter {
    my ( $self, $code ) = @_;
    my $marker = $self->marker;

    # Convert back to method
    $code =~ s{
        ^\s*\K                 # preserve leading whitespace
        sub               \s+  # keyword was convert to sub
        (?<subname> \w+ ) \b   # the method name and a word break
        (?<brace> .*? )   \s*  # anything orig following the declaration
        \#__$marker \s+        # our magic token
        (?<id> \d+)            # our sub identifier
        [ ]*                   # trailing spaces (not all whitespace)
    }{
        $self->emit_keyword( $+{subname}, $+{brace}, $+{id} );
    }egmx;

    # Check to see if tidy turned it into "sub name\n{ #..."
    $code =~ s{
        ^\s*\K                   # preserve leading whitespace
        sub                 \s+  # method was converted to sub
        (?<subname> \w+)\n  \s*  # the method name and a newline
        (?<brace> \{ .*?)   [ ]* # opening brace on newline followed orig comments
        \#__$marker         \s+  # our magic token
        (?<id> \d+)              # our sub identifier
        [ ]*                     # trailing spaces (not all whitespace)
    }{
        $self->emit_keyword( $+{subname}, $+{brace}, $+{id} );
    }egmx;

    return $code;
}

1;

__END__

=pod

=head1 NAME

Perl::Tidy::Sweetened::Keyword::SubSignature - Perl::Tidy::Sweetened filter plugin to define new subroutine keywords

=head1 VERSION

version 0.20

=head1 SYNOPSIS

    our $plugins = Perl::Tidy::Sweetened::Pluggable->new();

    $plugins->add_filter(
        Perl::Tidy::Sweetened::Keyword::SubSignature->new(
            keyword => 'method',
            marker  => 'METHOD',
            clauses => [ 'PAREN?', '(returns \s* PAREN)?' ],
        ) );

=head1 DESCRIPTION

This is a Perl::Tidy::Sweetened filter which enables the definition of
arbitrary keywords for subroutines with any number of potential signature
definitions. New accepts:

=over 4

=item keyword

    keyword => 'method'

Declares a new keyword (in this example the "method" keyword).

=item marker

    marker => 'METHOD'

Provides a text marker to be used to flag the new keywords during
C<prefilter>. The source code will be filtered prior to formatting by
Perl::Tidy such that:

    method foo {
    }

is turned into:

    sub foo { # __METHOD 1
    }

=item clauses

    clauses => [ 'PAREN?' ]

Provides a list of strings which will be turned into a regex to capture
additional clauses. The regex will include the 'xm' flags (so be sure to escape
spaces).  The clause can be marked optional with '?'. The special text "PAREN"
can be used to capture a balanced parenthetical.

This example will capture a parameter list enclosed by parenthesis, ie:

    method foo (Int $i) {
    }

No formatting is done on the clauses at this time. The order of declaration
is significant.

=back

=head1 THANKS

See L<Perl::Tidy::Sweetened>

=head1 BUGS

Please report any bugs or suggestions at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Perl-Tidy-Sweetened>

=head1 AUTHOR

Mark Grimes, E<lt>mgrimes@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Mark Grimes, E<lt>mgrimes@cpan.orgE<gt>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
