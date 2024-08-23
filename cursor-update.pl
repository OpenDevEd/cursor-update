#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use Getopt::Long;
use HTTP::Date;
use Digest::MD5;
use Pod::Usage;
use feature 'state';

my $APPDIR = "$ENV{HOME}/AppImages/cursor";
my $APPIMAGE_URL = "https://downloader.cursor.sh/linux/appImage/x64";
my $LOCAL_FILE = "$APPDIR/cursor.AppImage";
my $TEMP_FILE = "$APPDIR/cursor.AppImage.temp";

my $lazy = 0;
my $force = 0;
my $help = 0;

GetOptions(
    "lazy" => \$lazy,
    "force" => \$force,
    "help|?" => \$help
) or pod2usage(2);

pod2usage(1) if $help;

my $ua = LWP::UserAgent->new(
    agent => 'Wget/1.21.2'
);

if ($force) {
    download_cursor();
} else {
    check_and_update();
}

sub check_and_update {
    my $req = HTTP::Request->new(GET => $APPIMAGE_URL);
    $req->header('Range' => 'bytes=0-0');

    my $res = $ua->request($req);

    if ($res->is_success || $res->code == 206) {  # 206 is Partial Content
        my $remote_size = $res->header('Content-Range');
        $remote_size =~ s/bytes 0-0\///;  # Extract total size from Content-Range

        my $local_size = -s $LOCAL_FILE;

        my $update_needed = 0;

        if (!-e $LOCAL_FILE || $local_size != $remote_size) {
            $update_needed = 1;
        } elsif (!$lazy) {
            my $local_mtime = (stat($LOCAL_FILE))[9];
            my $remote_mtime = $res->header('Last-Modified');
            $remote_mtime = HTTP::Date::str2time($remote_mtime) if $remote_mtime;

            my $etag = $res->header('ETag');
            
            if ($remote_mtime && $remote_mtime > $local_mtime) {
                $update_needed = 1;
            } elsif ($etag) {
                open my $fh, '<', $LOCAL_FILE or die "Cannot open $LOCAL_FILE: $!";
                my $content = do { local $/; <$fh> };
                close $fh;
                my $local_etag = qq{"} . Digest::MD5::md5_hex($content) . qq{"};
                $update_needed = 1 if $etag ne $local_etag;
            }
        }

        if ($update_needed) {
            download_cursor();
        } else {
            print "Cursor is already up to date.\n";
        }
    } else {
        print "Error checking for updates: " . $res->status_line . "\n";
    }
}

sub download_cursor {
    print "Downloading latest Cursor version...\n";
    my $download_res = $ua->get($APPIMAGE_URL, 
        ':content_file' => $TEMP_FILE,
        ':content_cb' => sub {
            my ($data, $response, $protocol) = @_;
            state $total_size = $response->header('Content-Length');
            state $downloaded = 0;
            $downloaded += length($data);
            my $percent = $total_size ? int(100 * $downloaded / $total_size) : 0;
            printf "\rDownloading: %d%% complete", $percent;
        }
    );
    print "\n";  # Move to the next line after download completes
    if ($download_res->is_success) {
        rename $TEMP_FILE, $LOCAL_FILE;
        chmod 0755, $LOCAL_FILE;
        print "Download complete. Cursor has been updated.\n";
    } else {
        print "Error downloading: " . $download_res->status_line . "\n";
        unlink $TEMP_FILE;
    }
}

__END__

=head1 NAME

cursor-update.pl - Update the Cursor AppImage

=head1 SYNOPSIS

cursor-update.pl [options]

 Options:
   --lazy     Only perform basic size check
   --force    Always download the latest version
   --help     Show this help message

=head1 OPTIONS

=over 8

=item B<--lazy>

Only perform a basic size check when determining if an update is needed.

=item B<--force>

Always download and install the latest version, regardless of current version.

=item B<--help>

Print a brief help message and exits.

=back

=head1 DESCRIPTION

This script checks for updates to the Cursor AppImage and downloads the latest version if necessary.

=cut