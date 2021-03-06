#!/usr/bin/env perl
package Modules::Alignment::SNPFinder;

use FindBin;
use lib "$FindBin::Bin/../../";
use Modules::Fasta::SequenceName;
use Log::Log4perl;

sub new{
	my($class)  = shift;
    my $self= {};
    bless ($self, $class);
    $self->_initialize(@_);
    return $self;
}

#class vars
sub logger{
	my $self=shift;
	$self->{'_logger'} = shift // return $self->{'_logger'};
}

sub allowableChars{
	my $self=shift;
	$self->{'_allowableChars'} = shift // return $self->{'_allowableChars'};
}

sub orderedNames{
	my $self=shift;
	$self->{'_queryNameOrderHash'}=shift // return $self->{'_queryNameOrderHash'};
}

sub alignedFastaSequences{
	my $self=shift;
	$self->{'_alignedFastaSequences'}=shift // return $self->{'_alignedFastaSequences'};
}

sub resultNumber{
	my $self=shift;
	$self->{'_resultNumber'}=shift // return $self->{'_resultNumber'};
}

sub startBpHashRef{
	my $self=shift;
	$self->{'_startBpHashRef'}=shift // return $self->{'_startBpHashRef'};
}

sub _dashOffset{
	my $self=shift;
	$self->{'__dashOffset'}=shift // return $self->{'__dashOffset'};
}

#methods
sub _initialize{
	my($self)=shift;

	#logging
	$self->logger(Log::Log4perl->get_logger());
	$self->logger->debug("Logger initialized in Modules::Alignment::SNPFinder\n");
	
	my %params = @_;
    #on object construction set all parameters
    foreach my $key(keys %params){
		if($self->can($key)){
			$self->$key($params{$key});
		}
		else{
			#logconfess calls the confess of Carp package, as well as logging to Log4perl
			$self->logger->logconfess("$key is not a valid parameter in Modules::Alignment::SNPFinder");
		}
	}
	
	#defaults		
	$self->allowableChars({
		'A'=>1,
		'C'=>1,
		'T'=>1,
		'G'=>1,
		'a'=>1,
		'c'=>1,
		't'=>1,
		'g'=>1
	});

	#init data structures
	$self->_dashOffset({});
}

sub findSNPs{
	my($self)=shift;
	
	my ($alignmentLength,$alignedHashRef) = $self->_getHashOfFastaAlignment();
	$self->_setOffsetHash($alignedHashRef);

	my @orderedResults; 
	my $nameLine = $self->_getFastaNamesForOutput($alignedHashRef);
	for my $position(0..($alignmentLength-1)){
		my $resultLine = $self->_getSingleBaseResult($position,$alignedHashRef);

		if(defined $resultLine){
			$resultLine .= $nameLine;

			#add the contig names as tab-delimited values at the start of each new contig
			push @orderedResults,$resultLine;
		}
		
	}
	
	if(scalar(@orderedResults) > 0){
		return \@orderedResults;
	}
	else{
		return undef;
	}
	
}


=head3 _setOffsetHash

Stores the number of dashes in the Muscle alignment, so that the correct SNP position relative
to the original sequence can be given. We get the original startbp of the alignment via the blast
result, which is stored in the startBPhash.
During the SNP finding, we need to count each dash for each sequence and use it as an offset when
reporting the correct original SNP position.
Stored in _dashOffset->{sequenceName}=<dash count>

=cut

sub _setOffsetHash{
	my $self=shift;
	my $alignedHashRef=shift;

	foreach my $name(keys %{$alignedHashRef}){
		$self->_dashOffset->{$name}=0;
	}
}

=head3 _getFastaNamesForOutput

Returns an ordered list of contig names present in the current result for each genome.
The final output is as below:
name:data:position:contigNames
eg.
	
snp_1000000012	A 			A 			T 			A  			100004 		100004 			544 		 	100005	Acontig001 	Bcontig01004 	Ccontig0034 	Dcontig000043

=cut

sub _getFastaNamesForOutput{
	my $self=shift;
	my $alignedHashRef=shift;

	my $fastaNameLine='';

	# foreach my $key(keys %{$alignedHashRef}){
	# 	$self->logger->debug("alignedHashRefName: $key");
	# }

	foreach my $sName(@{$self->orderedNames}){
		#it could be there were no BLAST results for a given name
		#in that case, add 'N/A'
		if(defined $alignedHashRef->{$sName}->{'fasta'}){
			$fastaNameLine .=("\t" . $alignedHashRef->{$sName}->{'fasta'});
		}
		else{
			$self->logger->debug("$sName not found in alignedHashRef");
			$fastaNameLine .=("\t" . 'N/A');
		}
	}
	return $fastaNameLine;
}


=head3

Given a hash of the fasta sequence alignment,
and the position of the alignment, checks if a SNP exists.
SNPs must be of $self->allowableChars.
Returns a tab-delimited line of results, in the order of
$self->orderedNames.

=cut


sub _getSingleBaseResult{
	my $self = shift;
	my $position=shift;
	my $alignedHashRef=shift;

	my %baseTypes;
	my $baseLine='';
	my $positionLine='';

	foreach my $name(@{$self->orderedNames}){
		my $base;
		#in the case where there was no BLAST hit, there is no hash key to look up
		#need to fill in the position as '-'
		if(exists $alignedHashRef->{$name}->{'fasta'}){
			$base = substr($alignedHashRef->{$name}->{'sequence'},$position,1); 
			my $dashOffset = $self->_dashOffset->{$name};

			unless(defined $base){
				$self->logger->fatal("name: $name\nfasta: " . $alignedHashRef->{$name}->{'fasta'}. "\nseq: " . $alignedHashRef->{$name}->{'sequence'} . "\npos: $position");
			}

			if(defined $self->allowableChars->{$base}){
				#make sure base is uppercase
				$base = uc($base);
				$baseTypes{$base}=1;
			}
			
			$baseLine .= ("\t$base");	
			my $startBp = $self->startBpHashRef->{$alignedHashRef->{$name}->{'fasta'}};		

			#update _dashOffset if need be
			#if the char is a '-', there is no position information for the original sequence, so report a 0
			if($base eq '-'){
				$positionLine .= ("\t0");	
				#$self->logger->debug("Adjusting $name in " . $alignedHashRef->{$name}->{'fasta'} . " startbp $startBp position $position");
				$dashOffset++;
				$self->_dashOffset->{$name}=$dashOffset;
			}
			else{
				$positionLine .= ("\t" . ($startBp + $position - $dashOffset));	
			}		
		}
		else{
			$baseLine .= ("\t" . '-');
			$positionLine .= ("\t" . '-');
		}
	}

	if(scalar keys %baseTypes > 1){
		return (('snp_' . ($self->resultNumber + $position)) . $baseLine . $positionLine);
	}
	else{
		return undef;
	}
}


=head3

Given the FASTA alignment produced by Muscle, create a hash where the
name is based on the Modules::Fasta::SequenceName->name and
$hashRef->{'name'}->{'fasta'}="fasta header"
$hashRef->{'name'}->{'sequence'}="DNA sequence"
the {'fasta'} key contains the fasta header,
and the {'sequence'} key contains the DNA sequence.
Also compute the alignment length and return it as the first argument of the two argument return.

=cut

sub _getHashOfFastaAlignment{
	my $self = shift;

	my $results={};
	my $name;
	my $alignmentLength;

	my $numberOfLines = scalar @{$self->alignedFastaSequences};

	foreach my $line(@{$self->alignedFastaSequences}){
		$line =~ s/\R//g;
		
		if($line =~ /^>(.+)/){		
			$line =~ s/>//;
			my $sn = Modules::Fasta::SequenceName->new($line);
			$name = $sn->name;
			$self->logger->debug("New name: $name");
			#we don't need or want the '>'; all names are stored without the fasta header signifier
			$results->{$name}->{'fasta'}=$line;
		}
		else{
			$self->logger->debug("Not a header in SNPFinder");
			if(defined $results->{$name}->{'sequence'}){
			#	$self->logger->debug("Sequence already present, adding to it:\n$line");
				$results->{$name}->{'sequence'}=$results->{$name}->{'sequence'} . $line;	
			}
			else{
				#$self->logger->debug("New sequence, adding:\n$line");
				$results->{$name}->{'sequence'}=$line;
			}
					
		}
	}
	$alignmentLength=length($results->{$name}->{'sequence'});
	#$self->logger->debug("Alignment length of core is: $alignmentLength");
	return ($alignmentLength,$results);
}
1;
