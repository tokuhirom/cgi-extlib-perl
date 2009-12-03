package Plack::App::File;
use strict;
use warnings;
use parent qw/Plack::Middleware/;
use File::Spec::Unix;
use Path::Class 'dir';
use Plack::Util;
use HTTP::Date;
use MIME::Types;

__PACKAGE__->mk_accessors(qw( root encoding ));

sub should_handle {
    my($self, $file) = @_;
    return -f $file;
}

sub call {
    my $self = shift;
    my $env  = shift;

    my $path = $env->{PATH_INFO};
    if ($path =~ m!\.\.[/\\]!) {
        return $self->return_403;
    }

    my $docroot = dir($self->root || ".");
    my $file = $docroot->file(File::Spec::Unix->splitpath($path))->absolute;

    # Is the requested path within the root?
    if (!$docroot->subsumes($file)) {
        return $self->return_403;
    }

    # Does the file actually exist?
    if (!$self->should_handle($file)) {
        return $self->return_404;
    }

    # If the requested file present but lacking the permission to read it?
    if (!-r $file) {
        return $self->return_403;
    }

    return $self->serve_path($env, $file);
}

sub mime_type_for {
    my $self = shift;
    my $file = shift;
    my $type;
    if ($file =~ /.*\.(\S{1,})$/xms ) {
        $type = (MIME::Types::by_suffix $1)[0];
    }
    return $type || 'text/plain';
}

sub serve_path {
    my($self, $env, $file) = @_;

    my $content_type = $self->mime_type_for($file);

    if ($content_type =~ m!^text/!) {
        $content_type .= "; charset=" . ($self->encoding || "utf-8");
    }

    my $fh = $file->openr
        or return $self->return_403;

    my $path = $file->stringify;
       $path =~ s!\\!/!g;
    Plack::Util::set_io_path($fh, $path);
    binmode $fh;

    my $stat = $file->stat;
    return [
        200,
        [
            'Content-Type'   => $content_type,
            'Content-Length' => $stat->size,
            'Last-Modified'  => HTTP::Date::time2str( $stat->mtime )
        ],
        $fh,
    ];
}

sub return_403 {
    my $self = shift;
    return [403, ['Content-Type' => 'text/plain'], ['forbidden']];
}

# Hint: subclasses can override this to return undef to pass through 404
sub return_404 {
    my $self = shift;
    return [404, ['Content-Type' => 'text/plain'], ['not found']];
}

1;
__END__

=head1 NAME

Plack::App::File - Serve static files from root directory

=head1 SYNOPSIS

  use Plack::App::File;
  my $app = Plack::App::File->new({ root => "/path/to/htdocs" })->to_app;

=head1 DESCRIPTION

This is a static file server PSGI application, and internally used by
L<Plack::Middleware::Static>. This application serves file from
document root if the path matches with the local file. Use
L<Plack::App::Directory> if you want to list files in the directory
as well.

=head1 CONFIGURATION

=over 4

=item root

Document root directory. Defaults to C<.> (current directory)

=item encoding

Set the file encoding for text files. Defaults to C<utf-8>.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa

=head1 SEE ALSO

L<Plack::Middleware::Static> L<Plack::App::Directory>

=cut


