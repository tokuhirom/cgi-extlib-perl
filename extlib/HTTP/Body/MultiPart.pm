package HTTP::Body::MultiPart;
BEGIN {
  $HTTP::Body::MultiPart::VERSION = '1.12';
}

use strict;
use base 'HTTP::Body';
use bytes;

use IO::File;
use File::Temp 0.14;
use File::Spec;

=head1 NAME

HTTP::Body::MultiPart - HTTP Body Multipart Parser

=head1 SYNOPSIS

    use HTTP::Body::Multipart;

=head1 DESCRIPTION

HTTP Body Multipart Parser.

=head1 METHODS

=over 4

=item init

=cut

sub init {
    my $self = shift;

    unless ( $self->content_type =~ /boundary=\"?([^\";]+)\"?/ ) {
        my $content_type = $self->content_type;
        Carp::croak("Invalid boundary in content_type: '$content_type'");
    }

    $self->{boundary} = $1;
    $self->{state}    = 'preamble';

    return $self;
}

=item spin

=cut

sub spin {
    my $self = shift;

    while (1) {

        if ( $self->{state} =~ /^(preamble|boundary|header|body)$/ ) {
            my $method = "parse_$1";
            return unless $self->$method;
        }

        else {
            Carp::croak('Unknown state');
        }
    }
}

=item boundary

=cut

sub boundary {
    return shift->{boundary};
}

=item boundary_begin

=cut

sub boundary_begin {
    return "--" . shift->boundary;
}

=item boundary_end

=cut

sub boundary_end {
    return shift->boundary_begin . "--";
}

=item crlf

=cut

sub crlf () {
    return "\x0d\x0a";
}

=item delimiter_begin

=cut

sub delimiter_begin {
    my $self = shift;
    return $self->crlf . $self->boundary_begin;
}

=item delimiter_end

=cut

sub delimiter_end {
    my $self = shift;
    return $self->crlf . $self->boundary_end;
}

=item parse_preamble

=cut

sub parse_preamble {
    my $self = shift;

    my $index = index( $self->{buffer}, $self->boundary_begin );

    unless ( $index >= 0 ) {
        return 0;
    }

    # replace preamble with CRLF so we can match dash-boundary as delimiter
    substr( $self->{buffer}, 0, $index, $self->crlf );

    $self->{state} = 'boundary';

    return 1;
}

=item parse_boundary

=cut

sub parse_boundary {
    my $self = shift;

    if ( index( $self->{buffer}, $self->delimiter_begin . $self->crlf ) == 0 ) {

        substr( $self->{buffer}, 0, length( $self->delimiter_begin ) + 2, '' );
        $self->{part}  = {};
        $self->{state} = 'header';

        return 1;
    }

    if ( index( $self->{buffer}, $self->delimiter_end . $self->crlf ) == 0 ) {

        substr( $self->{buffer}, 0, length( $self->delimiter_end ) + 2, '' );
        $self->{part}  = {};
        $self->{state} = 'done';

        return 0;
    }

    return 0;
}

=item parse_header

=cut

sub parse_header {
    my $self = shift;

    my $crlf  = $self->crlf;
    my $index = index( $self->{buffer}, $crlf . $crlf );

    unless ( $index >= 0 ) {
        return 0;
    }

    my $header = substr( $self->{buffer}, 0, $index );

    substr( $self->{buffer}, 0, $index + 4, '' );

    my @headers;
    for ( split /$crlf/, $header ) {
        if (s/^[ \t]+//) {
            $headers[-1] .= $_;
        }
        else {
            push @headers, $_;
        }
    }

    my $token = qr/[^][\x00-\x1f\x7f()<>@,;:\\"\/?={} \t]+/;

    for my $header (@headers) {

        $header =~ s/^($token):[\t ]*//;

        ( my $field = $1 ) =~ s/\b(\w)/uc($1)/eg;

        if ( exists $self->{part}->{headers}->{$field} ) {
            for ( $self->{part}->{headers}->{$field} ) {
                $_ = [$_] unless ref($_) eq "ARRAY";
                push( @$_, $header );
            }
        }
        else {
            $self->{part}->{headers}->{$field} = $header;
        }
    }

    $self->{state} = 'body';

    return 1;
}

=item parse_body

=cut

sub parse_body {
    my $self = shift;

    my $index = index( $self->{buffer}, $self->delimiter_begin );

    if ( $index < 0 ) {

        # make sure we have enough buffer to detect end delimiter
        my $length = length( $self->{buffer} ) - ( length( $self->delimiter_end ) + 2 );

        unless ( $length > 0 ) {
            return 0;
        }

        $self->{part}->{data} .= substr( $self->{buffer}, 0, $length, '' );
        $self->{part}->{size} += $length;
        $self->{part}->{done} = 0;

        $self->handler( $self->{part} );

        return 0;
    }

    $self->{part}->{data} .= substr( $self->{buffer}, 0, $index, '' );
    $self->{part}->{size} += $index;
    $self->{part}->{done} = 1;

    $self->handler( $self->{part} );

    $self->{state} = 'boundary';

    return 1;
}

=item handler

=cut

sub handler {
    my ( $self, $part ) = @_;

    unless ( exists $part->{name} ) {

        my $disposition = $part->{headers}->{'Content-Disposition'};
        my ($name)      = $disposition =~ / name="?([^\";]+)"?/;
        my ($filename)  = $disposition =~ / filename="?([^\"]*)"?/;
        # Need to match empty filenames above, so this part is flagged as an upload type

        $part->{name} = $name;

        if ( defined $filename ) {
            $part->{filename} = $filename;

            if ( $filename ne "" ) {
                my $basename = (File::Spec->splitpath($filename))[2];
                my $suffix = $basename =~ /[^.]+(\.[^\\\/]+)$/ ? $1 : q{};

                my $fh = File::Temp->new( UNLINK => 0, DIR => $self->tmpdir, SUFFIX => $suffix );

                $part->{fh}       = $fh;
                $part->{tempname} = $fh->filename;
            }
        }
    }

    if ( $part->{fh} && ( my $length = length( $part->{data} ) ) ) {
        $part->{fh}->write( substr( $part->{data}, 0, $length, '' ), $length );
    }

    if ( $part->{done} ) {

        if ( exists $part->{filename} ) {
            if ( $part->{filename} ne "" ) {
                $part->{fh}->close if defined $part->{fh};

                delete @{$part}{qw[ data done fh ]};

                $self->upload( $part->{name}, $part );
            }
        }
        else {
            $self->param( $part->{name}, $part->{data} );
        }
    }
}

=back

=head1 AUTHOR

Christian Hansen, C<ch@ngmedia.com>

=head1 LICENSE

This library is free software . You can redistribute it and/or modify 
it under the same terms as perl itself.

=cut

1;
