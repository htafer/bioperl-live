#
#  BioPerl module for Bio::AlignIO::meme
#   Based on the Bio::SeqIO modules
#  by Ewan Birney <birney@ebi.ac.uk>
#  and Lincoln Stein  <lstein@cshl.org>
#  and the SimpleAlign.pm module of Ewan Birney
#
# Copyright Benjamin Berman
#
# You may distribute this module under the same terms as perl itself

=head1 NAME

Bio::AlignIO::meme - meme sequence input/output stream

=head1 SYNOPSIS

Do not use this module directly.  Use it via the Bio::AlignIO class.

  use Bio::AlignIO;
  # read in an alignment from meme
  my $in = Bio::AlignIO->new(-format => 'meme',
                             -file   => 'meme.out');
  while( my $aln = $in->next_aln ) {
     # do something with the alignment
  }

=head1 DESCRIPTION

This object transforms the "sites sorted by position p-value" sections
of a meme (text) output file into a series of Bio::SimpleAlign
objects.  Each SimpleAlign object contains Bio::LocatableSeq
objects which represent the individual aligned sites as defined by
the central portion of the "site" field in the meme file.  The start
and end coordinates are derived from the "Start" field. See
L<Bio::SimpleAlign> and L<Bio::LocatableSeq> for more information.

This module can only parse MEME version 3 and 4.  Previous
versions have output formats that are more difficult to parse
correctly.  If the meme output file is not version 3.0 or greater
we signal an error.

=head1 FEEDBACK

=head2 Support 

Please direct usage questions or support issues to the mailing list:

I<bioperl-l@bioperl.org>

rather than to the module maintainer directly. Many experienced and 
reponsive experts will be able look at the problem and quickly 
address it. Please include a thorough description of the problem 
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
the bugs and their resolution.  Bug reports can be submitted via the
web:

  https://redmine.open-bio.org/projects/bioperl/

=head1 AUTHORS - Benjamin Berman

 Bbased on the Bio::SeqIO modules by Ewan Birney and others
 Email: benb@fruitfly.berkeley.edu

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with an
underscore.

=cut

# Let the code begin...

package Bio::AlignIO::meme;
use strict;
use Bio::LocatableSeq;

use base qw(Bio::AlignIO);

# Constants
my $MEME_VERS_ERR =
  "MEME must be version 3 or 4";
my $MEME_NO_HEADER_ERR =
  "MEME output file contains no header line (example: MEME version 3.0)";
my $HTML_VERS_ERR = 
  "MEME output file must be generated with the -text option";

=head2 next_aln

 Title   : next_aln
 Usage   : $aln = $stream->next_aln()
 Function: returns the next alignment in the stream
 Returns : Bio::SimpleAlign object with the score() set to the evalue of the
           motif.
 Args    : NONE

=cut

sub next_aln {
    my ($self) = @_;
    my $aln = Bio::SimpleAlign->new( -source => 'meme' );
    my $line;
    my $good_align_sec = 0;
    my $in_align_sec   = 0;
    my $evalue;
    while ( !$good_align_sec && defined( $line = $self->_readline() ) ) {
        if ( !$in_align_sec ) {

            # Check for the meme header
            if ( $line =~ /^\s*MEME\s+version\s+(\S+)/ ) {
                $self->{'meme_vers'} = $1;
                my ($vers) = $self->{'meme_vers'} =~ /^(\d)/;
                $self->throw($MEME_VERS_ERR) if ( $vers != 3 && $vers != 4 );
                $self->{'seen_header'} = 1;
            }

            # Check if they've output the HTML version
            if ( $line =~ /\<TITLE\>/i ) {
                $self->throw($HTML_VERS_ERR);
            }

            # Grab the evalue
            if ( $line =~ /MOTIF\s+\d+\s+width.+E-value = (\S+)/ ) {
                $self->throw($MEME_NO_HEADER_ERR)
                  unless ( $self->{'seen_header'} );
                $evalue = $1;
            }

            # Check if we're going into an alignment section
            if ( $line =~ /sites sorted by position/ ) {
                $self->throw($MEME_NO_HEADER_ERR)
                  unless ( $self->{'seen_header'} );
                $in_align_sec = 1;
            }
        }
        # The first regexp is for version 3, the second is for version 4
        elsif ( $line =~ /^(\S+)\s+([+-]?)\s+(\d+)\s+
                           \S+\s+[.A-Z\-]*\s+([A-Z\-]+)\s+
                           ([.A-Z\-]*)/xi
                ||
                $line =~ /^(\S+)\s+([+-]?)\s+(\d+)\s+
                           \S+\s+\.\s+([A-Z\-]+)/xi
          )
        {
            # Got a sequence line
            my $seq_name  = $1;
            my $strand    = ( $2 eq '-' ) ? -1 : 1;
            my $start_pos = $3;
            my $central   = uc($4);

            # my $p_val = $4;
            # my $left_flank = uc($5);
            # my $right_flank = uc($7);

            # Info about the flanking sequence
            # my $start_len = ($strand > 0) ? length($left_flank) :
            # length($right_flank);
            # my $end_len = ($strand > 0) ? length($right_flank) :
            # length($left_flank);

            # Make the sequence.  Meme gives the start coordinate at the left
            # hand side of the motif relative to the INPUT sequence.
            my $end_pos = $start_pos + length($central) - 1;
            my $seq     = Bio::LocatableSeq->new(
                -seq        => $central,
                -display_id => $seq_name,
                -start      => $start_pos,
                -end        => $end_pos,
                -strand     => $strand,
                -alphabet   => $self->alphabet,
            );

            # Add the sequence motif to the alignment
            $aln->add_seq($seq);
        }
        elsif ( ( $line =~ /^\-/ ) || ( $line =~ /Sequence name/ ) ) {

            # These are acceptable things to be in the site section
        }
        elsif ( $line =~ /^\s*$/ ) {

            # This ends the site section
            $in_align_sec   = 0;
            $good_align_sec = 1;
        }
        else {
            $self->warn("Unrecognized format:\n$line");
            return 0;
        }
    }

    # Signal an error if we didn't find a header section
    $self->throw($MEME_NO_HEADER_ERR) unless ( $self->{'seen_header'} );

    if ($good_align_sec) {
        $aln->score($evalue);
        return $aln;
    }

    return;
}

=head2 write_aln

 Title   : write_aln
 Usage   : $stream->write_aln(@aln)
 Function: Not implemented
 Returns : 1 for success and 0 for error
 Args    : Bio::SimpleAlign object

=cut

sub write_aln {
    my ( $self, @aln ) = @_;
    $self->throw_not_implemented();
}

# ----------------------------------------
# -   Private methods
# ----------------------------------------

sub _initialize {
    my ( $self, @args ) = @_;

    # Call into our base version
    $self->SUPER::_initialize(@args);

    # Then initialize our data variables
    $self->{'seen_header'} = 0;
}

1;
